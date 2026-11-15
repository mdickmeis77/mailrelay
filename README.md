# Vemas.MailRelay

SMTP-Relay für **SQL Server Database Mail** und **SSRS**, die sich nicht modern an Exchange Online
anmelden können. Beide liefern Mails per SMTP mit Basic Auth an den Dienst; der Dienst versendet
sie über **Microsoft Graph** mit OAuth (Client Credentials, Client Secret).

```
SQL Server (Database Mail) ─┐
                            ├─ SMTP 587 + AUTH LOGIN ─►  Vemas.MailRelay  ─► Microsoft Graph ─► Exchange Online
SSRS (Abo-Versand) ─────────┘                            │
                                                         ▼
                                          NextGen-DB, Schema [mailrelay]
                                          Queue · Protokoll · Neu senden
```

- .NET 10, Windows-Dienst, eine self-contained EXE (keine .NET-Installation auf dem Server nötig)
- Queue und Protokoll in der NextGen-Datenbank (Schema `mailrelay`)
- Weboberfläche (Port 8587, Windows-Anmeldung) für Protokoll, Neu senden, Profile, SMTP-Benutzer, Testmail
- Meldungen in der Windows-Ereignisanzeige (Quelle `Vemas.MailRelay`)

---

## Inhalt

1. [Entra ID: App-Registrierung](#1-entra-id-app-registrierung)
2. [Exchange Online: Absender einschränken](#2-exchange-online-absender-einschränken)
3. [Datenbank installieren](#3-datenbank-installieren)
4. [EXE erstellen](#4-exe-erstellen)
5. [Dienst installieren](#5-dienst-installieren)
6. [Profil und SMTP-Benutzer anlegen](#6-profil-und-smtp-benutzer-anlegen)
7. [SQL Server Database Mail umstellen](#7-sql-server-database-mail-umstellen)
8. [SSRS umstellen](#8-ssrs-umstellen)
9. [Betrieb](#9-betrieb)
10. [Fehlerbilder](#10-fehlerbilder)

---

## 1. Entra ID: App-Registrierung

Pro Tenant ein Profil, pro Profil eine App-Registrierung.

1. Entra Admin Center → **App-Registrierungen** → **Neue Registrierung**, Name z.B. `Vemas.MailRelay`, nur dieses Verzeichnis.
2. **Zertifikate & Geheimnisse** → **Neuer geheimer Clientschlüssel**. Den **Wert** (nicht die ID) sofort kopieren und das Ablaufdatum notieren.
3. **Übersicht**: Anwendungs-ID (Client-ID) und Verzeichnis-ID (Tenant-ID) notieren.
4. Berechtigung: siehe Abschnitt 2 – entweder Exchange-RBAC (empfohlen) **oder** `Mail.Send` (Anwendung) in Entra.

## 2. Exchange Online: Absender einschränken

> **Wichtig:** Die Entra-Berechtigung `Mail.Send` (Anwendung) erlaubt der App, im Namen **jedes** Postfachs
> des Tenants zu senden. Deshalb die Berechtigung über Exchange auf die benötigten Postfächer begrenzen.

### Empfohlen: RBAC for Applications

Bei dieser Variante wird **keine** `Mail.Send`-Berechtigung in Entra erteilt (Entra- und Exchange-Rechte
addieren sich – eine Entra-Zustimmung würde die Einschränkung aushebeln).

```powershell
Connect-ExchangeOnline

# Objekt-ID der Unternehmensanwendung (Entra > Unternehmensanwendungen > Vemas.MailRelay), NICHT die der App-Registrierung
New-ServicePrincipal -AppId "<Client-ID>" -ObjectId "<Objekt-ID Unternehmensanwendung>" -DisplayName "Vemas.MailRelay"

# Bereich: nur Mitglieder einer (E-Mail-aktivierten Sicherheits-)Gruppe
New-ManagementScope -Name "MailRelay-Absender" `
    -RecipientRestrictionFilter "MemberOfGroup -eq 'CN=MailRelay-Absender,OU=...,DC=...'"

New-ManagementRoleAssignment -App "<Client-ID>" -Role "Application Mail.Send" -CustomResourceScope "MailRelay-Absender"

# Prüfen
Test-ServicePrincipalAuthorization -Identity "<Client-ID>" -Resource "reports@firma.de"
```

Bei **SendAs**-Profilen alle erlaubten Absender in die Gruppe aufnehmen, bei **Fester Absender** nur das Standard-Postfach.
Änderungen können bis zu 2 Stunden dauern, bis sie wirken.

### Alternative: Mail.Send in Entra + Application Access Policy

`Mail.Send` (Anwendung) in Entra erteilen, Administratorzustimmung geben, dann:

```powershell
New-ApplicationAccessPolicy -AppId "<Client-ID>" -PolicyScopeGroupId "mailrelay-absender@firma.de" `
    -AccessRight RestrictAccess -Description "Vemas.MailRelay"
```

Microsoft ersetzt Application Access Policies schrittweise durch RBAC for Applications.

## 3. Datenbank installieren

`install/Install-Database.sql` in SSMS **auf der NextGen-Datenbank** ausführen (db_owner, für `CREATE LOGIN` zusätzlich securityadmin).

Vorher in Abschnitt 6 des Skripts das Dienstkonto eintragen:

```sql
DECLARE @ServiceUser SYSNAME = N'CONTOSO\svc-mailrelay';
```

Das Skript ist wiederholbar und legt an:

| Objekt | Zweck |
|---|---|
| `mailrelay.Profile` | Versandprofile (Tenant, Client-ID, verschlüsseltes Secret, Absender-Modus) |
| `mailrelay.SmtpUser` | SMTP-Logins mit Passwort-Hash und IP-Freigabe |
| `mailrelay.AllowedSender` | erlaubte Absender je Profil (`adresse@firma.de` oder `*@firma.de`) |
| `mailrelay.Message` | Queue und Protokoll inkl. MIME-Inhalt |
| `mailrelay.Attempt` | alle Versuche und manuellen Aktionen |
| `mailrelay.Resend` / `Cancel` / `Cleanup` | Neu senden, Abbrechen, Aufräumen |

Das Dienstkonto erhält nur `SELECT, INSERT, UPDATE, DELETE, EXECUTE` auf das Schema – keine DDL-Rechte.

## 4. EXE erstellen

```powershell
dotnet publish src/Vemas.MailRelay -c Release -o publish
```

Ergebnis im Ordner `publish`: `Vemas.MailRelay.exe` (self-contained, win-x64), `appsettings.json`,
`Install-Service.ps1`, `Uninstall-Service.ps1` und `Install-Database.sql`. Diesen Ordner komplett auf den
Server kopieren, z.B. nach `C:\VemasDienste\VemasMailRelay`.

## 5. Dienst installieren

### Voraussetzungen für das Dienstkonto

- Recht **„Als Dienst anmelden“** (Lokale Sicherheitsrichtlinie oder GPO → Zuweisen von Benutzerrechten).
  Ohne dieses Recht startet der Dienst mit Fehler 1069.
- SQL-Zugriff (vergibt `Install-Database.sql`).

### appsettings.json

Die `appsettings.json` neben der EXE im Dienstordner anpassen:

| Schlüssel | Bedeutung |
|---|---|
| `ConnectionStrings:MailRelay` | NextGen-Datenbank, Windows-Authentifizierung |
| `Web:AdminGroup` | AD-Gruppe mit Zugriff auf die Weboberfläche, z.B. `CONTOSO\MailRelay-Admins` |
| `Smtp:Port` / `Web:Port` | Standard 587 / 8587 |
| `Smtp:CertificateThumbprint` | optional: Zertifikat (LocalMachine\My) für STARTTLS |
| `Smtp:RequireTls` | optional: AUTH nur nach STARTTLS |
| `Web:CertificateThumbprint` | optional: Zertifikat für HTTPS |
| `Sending:RetryDelaysMinutes` | Wartezeiten vor den Wiederholungen, Standard `[1, 5, 15, 60, 240]` |
| `Sending:MaxParallel` | parallele Versendungen, Standard 4 |
| `Maintenance:MimeRetentionDays` | MIME-Inhalt löschen nach, Standard 30 Tage |
| `Maintenance:LogRetentionDays` | Protokoll löschen nach, Standard 365 Tage |
| `Maintenance:SecretExpiryWarningDays` | Warnung vor Secret-Ablauf, Standard 30 Tage |

Bei Updates die vorhandene `appsettings.json` nicht mit der aus dem publish-Ordner überschreiben.

### Installation

PowerShell **als Administrator**, im Dienstordner auf dem Server:

```powershell
cd C:\VemasDienste\VemasMailRelay
.\Install-Service.ps1 -ServiceAccount "CONTOSO\svc-mailrelay" -SmtpAllowedRemoteAddress "10.0.0.5","10.0.0.6"
```

Liegt die EXE neben dem Skript, läuft der Dienst direkt aus diesem Ordner – es wird nichts kopiert.
Die ersten Ausgaben zeigen, welche Ordner verwendet werden:

```
Quelle: C:\VemasDienste\VemasMailRelay
Dienst läuft aus: C:\VemasDienste\VemasMailRelay
```

Andere Ordner lassen sich ausdrücklich angeben; dann kopiert das Skript die EXE (und beim ersten Mal die
`appsettings.json`) von `-SourcePath` nach `-InstallPath`:

```powershell
.\Install-Service.ps1 -ServiceAccount "CONTOSO\svc-mailrelay" -SmtpAllowedRemoteAddress "10.0.0.5" `
    -SourcePath "D:\Download\MailRelay" -InstallPath "C:\VemasDienste\VemasMailRelay"
```

Das Skript registriert die Ereignisquelle, legt den Dienst an (Autostart, Neustart nach Absturz), erstellt
Firewall-Regeln und startet den Dienst. Für ein gMSA das Konto mit `$` angeben
(`CONTOSO\gmsa-mailrelay$`) – dann wird kein Passwort abgefragt.

Update: Dienst stoppen (`Stop-Service Vemas.MailRelay` – die laufende EXE lässt sich nicht überschreiben),
neue EXE in den Dienstordner kopieren (die `appsettings.json` behalten) und das Skript erneut ausführen;
es startet den Dienst wieder.
Deinstallation: `.\Uninstall-Service.ps1 [-RemoveFiles]`.

### Kerberos für die Weboberfläche (optional)

Läuft der Dienst unter einem Domänenkonto, für Kerberos einen SPN setzen (sonst wird NTLM verwendet, was ebenfalls funktioniert):

```powershell
setspn -S HTTP/mailrelay01 CONTOSO\svc-mailrelay
setspn -S HTTP/mailrelay01.contoso.local CONTOSO\svc-mailrelay
```

## 6. Profil und SMTP-Benutzer anlegen

Weboberfläche: `http://<server>:8587/`

1. **Profile → Neues Profil**: Tenant-ID, Client-ID, Client Secret, Ablaufdatum, Modus, Standard-Absender.
   - **Fester Absender**: Jede Mail geht über das Standard-Postfach. Der ursprüngliche Absender wird zur Antwortadresse (Reply-To).
   - **SendAs**: Der Absender aus der Mail wird übernommen, wenn er dem Standard-Absender oder einem Eintrag der Liste
     *Erlaubte Absender* entspricht. Andere Absender werden schon beim SMTP-Eingang mit `5.7.1 Absender nicht erlaubt` abgewiesen.
2. **Testmail senden** auf der Profilseite – prüft Anmeldung und Exchange-Berechtigung. Ergebnis im Verlauf.
3. **SMTP-Benutzer → Neuer Benutzer**: Login, Passwort (mind. 12 Zeichen), Profil, erlaubte IPs der SQL-/SSRS-Server.
   Ohne IP-Eintrag ist keine Anmeldung möglich.

Secrets werden per DPAPI (Maschinenschlüssel) verschlüsselt, Passwörter als PBKDF2-Hash gespeichert.
Nach einem **Serverumzug** müssen alle Client Secrets neu eingetragen werden.

## 7. SQL Server Database Mail umstellen

SSMS → Verwaltung → Datenbank-E-Mail → Konto bearbeiten, oder per T-SQL:

```sql
EXEC msdb.dbo.sysmail_update_account_sp
    @account_name            = N'<vorhandenes Konto>',
    @email_address           = N'reports@firma.de',      -- muss zum Profil passen
    @mailserver_name         = N'mailrelay01',
    @port                    = 587,
    @enable_ssl              = 0,                        -- 1 nur mit Smtp:CertificateThumbprint
    @username                = N'sqlmail',               -- SMTP-Benutzer aus der Weboberfläche
    @password                = N'<Passwort>',
    @use_default_credentials = 0;
```

Test: `EXEC msdb.dbo.sp_send_dbmail @recipients = 'ich@firma.de', @subject = 'Test', @body = 'Test';`

Bcc-Empfänger (`@blind_copy_recipients`) werden korrekt übernommen.

## 8. SSRS umstellen

Report Server Configuration Manager → **E-Mail-Einstellungen**:

| Feld | Wert |
|---|---|
| Absenderadresse | `reports@firma.de` (muss zum Profil passen) |
| Verwendeter SMTP-Server | `mailrelay01` |
| Authentifizierung | Benutzername und Kennwort (Basic) |
| Benutzername / Kennwort | SMTP-Benutzer aus der Weboberfläche |

Port und SSL in `rsreportserver.config` (unter `<RSEmailDPConfiguration>`), danach den SSRS-Dienst neu starten:

```xml
<SMTPServerPort>587</SMTPServerPort>
<SMTPUseSSL>False</SMTPUseSSL>
<SendUsing>2</SendUsing>
<SMTPAuthenticate>1</SMTPAuthenticate>
```

## 9. Betrieb

### Ablauf einer Mail

| Status | Bedeutung |
|---|---|
| Wartend (`Queued`) | angenommen, wird sofort versendet |
| Wird gesendet (`Sending`) | in Bearbeitung (Sperre 15 Minuten; nach Absturz wird sie wieder aufgenommen) |
| Wiederholung (`Retry`) | vorübergehender Fehler, nächster Versuch geplant |
| Gesendet (`Sent`) | von Graph angenommen, Kopie in „Gesendete Elemente“ |
| Fehlgeschlagen (`Failed`) | dauerhafter Fehler oder alle Wiederholungen erschöpft |
| Abgebrochen (`Cancelled`) | manuell abgebrochen |

- **Wiederholungen**: erster Versuch sofort, danach bis zu 5 Wiederholungen nach 1, 5, 15, 60 und 240 Minuten.
- **Ohne Wiederholung** (sofort `Failed`): ungültiges Secret, App ohne Berechtigung, unbekanntes Postfach, Absender nicht erlaubt.
- **Neu senden**: In Protokoll oder Detailansicht, auch für mehrere Mails. Setzt Status und Versuchszähler zurück.
  Möglich, solange der MIME-Inhalt gespeichert ist (Standard 30 Tage). Per SQL: `EXEC mailrelay.Resend @MessageId = 4711;`
- **Große Mails** (über ca. 2,9 MB MIME): Der Dienst legt einen Entwurf an, lädt die Anhänge einzeln bzw. per Upload-Session hoch
  (bis 150 MB) und sendet ihn dann.
- **Wichtig**: SQL Server und SSRS melden „gesendet“, sobald der Dienst die Mail angenommen hat.
  Fehler beim Versand an Exchange stehen **nur im Protokoll des Dienstes**, nicht in `sysmail_event_log` oder im SSRS-Abostatus.

### Secret/Passwort per SQL setzen

Für Automatisierung oder Notfälle können Klartextwerte direkt eingetragen werden. Der Dienst übernimmt sie
innerhalb einer Minute, verschlüsselt bzw. hasht sie und leert das Feld:

```sql
UPDATE mailrelay.Profile  SET SecretPlain   = N'<neues Secret>', SecretExpiresAt = '2028-11-15' WHERE Name  = N'Firma';
UPDATE mailrelay.SmtpUser SET PasswordPlain = N'<neues Passwort>'                                WHERE Login = N'sqlmail';
```

### Konsole statt Dienst (Fehlersuche)

`Vemas.MailRelay.exe` direkt in einer Konsole starten – alle Meldungen erscheinen im Fenster. Vorher den Dienst stoppen (Ports).

## 10. Fehlerbilder

| Meldung | Ursache / Lösung |
|---|---|
| `AADSTS7000215: Invalid client secret` | Secret falsch oder abgelaufen → neues Secret in Entra erstellen und im Profil eintragen |
| `AADSTS700016: Application ... not found` | Client-ID oder Tenant-ID falsch |
| `Graph 403 ErrorAccessDenied` / `Access is denied` | App hat keine Berechtigung für dieses Postfach → Abschnitt 2 prüfen (Gruppe, Wartezeit) |
| `Graph 404 ErrorInvalidUser` / `ResourceNotFound` | Absenderpostfach existiert nicht |
| `Client Secret kann auf diesem Server nicht entschlüsselt werden` | DB von anderem Server übernommen → Secret neu eintragen |
| `MIME-Inhalt nicht mehr vorhanden` | Aufbewahrungsfrist abgelaufen, Neu senden nicht mehr möglich |
| SMTP `535 Authentication failed` | Ereignisanzeige zeigt den Grund: Benutzer unbekannt/deaktiviert, IP nicht freigegeben, Passwort falsch |
| SMTP `5.7.1 Absender nicht erlaubt` | Absender passt nicht zum SendAs-Profil → Liste *Erlaubte Absender* ergänzen |
| Dienst startet nicht, Fehler 1069 | Dienstkonto fehlt das Recht „Als Dienst anmelden“ |
| Weboberfläche: 403 | Benutzer ist nicht in `Web:AdminGroup` (nach Gruppenänderung neu anmelden) |
