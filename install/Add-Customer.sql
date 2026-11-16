-- ============================================================
-- Vemas.MailRelay - Kunden für den Zugriff aus NextGen einrichten
--
-- Ausführen: in SSMS, verbunden mit der DATENBANK DES RELAYS
--   * Cloud:              eigene Relay-Datenbank
--   * Einzelinstallation: NextGen-Datenbank (Schema mailrelay liegt dort)
-- Benötigt: db_owner in Relay- und NextGen-Datenbank (für CREATE LOGIN zusätzlich securityadmin).
--
-- Das Skript ist wiederholbar. Es
--   1. legt den Kunden an und ordnet den Windows-Login des NextGen-App-Pools zu,
--   2. gibt dem Login Rechte nur auf die Kunden-Schnittstelle (Schema mailrelay_kunde),
--      in der Cloud mit Prüfung: kein db_owner, kein sysadmin,
--   3. legt in der NextGen-Datenbank das Schema mailrelay_ng mit Synonymen auf die Schnittstelle an.
-- Danach: NextGen-Paket.sql in der NextGen-Datenbank ausführen und in der Relay-Weboberfläche
-- die Profile des Kunden zuordnen.
--
-- >>> VOR DEM AUSFÜHREN DIE VIER WERTE ANPASSEN <<<
-- ============================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @CustomerName NVARCHAR(200) = N'Musterkunde GmbH';           -- Anzeigename
DECLARE @ShortName    NVARCHAR(50)  = N'MUSTER';                     -- Kurzname (erscheint im Verlauf)
DECLARE @Login        SYSNAME       = N'DOMAENE\svc-nextgen-muster'; -- Windows-Login des NextGen-App-Pools
DECLARE @NextGenDb    SYSNAME       = N'NextGen_Muster';             -- NextGen-Datenbank des Kunden

-- ------------------------------------------------------------
-- Prüfungen
-- ------------------------------------------------------------
DECLARE @RelayDb SYSNAME = DB_NAME();
DECLARE @IsCloud BIT = CASE WHEN @RelayDb = @NextGenDb THEN 0 ELSE 1 END;

IF @Login LIKE N'DOMAENE\%'
    THROW 50100, N'Bitte die vier Werte am Anfang des Skripts anpassen.', 1;
IF OBJECT_ID(N'mailrelay.Customer', N'U') IS NULL OR SCHEMA_ID(N'mailrelay_kunde') IS NULL
    THROW 50101, N'Dies ist nicht die Datenbank des Relays, oder Install-Database.sql wurde noch nicht in der aktuellen Version ausgeführt.', 1;
IF DB_ID(@NextGenDb) IS NULL
    THROW 50102, N'Die angegebene NextGen-Datenbank existiert nicht.', 1;

IF SUSER_ID(@Login) IS NULL
BEGIN
    EXEC (N'CREATE LOGIN ' + N'[' + @Login + N'] FROM WINDOWS');
    PRINT N'Login ' + @Login + N' angelegt.';
END

IF @IsCloud = 1 AND IS_SRVROLEMEMBER(N'sysadmin', @Login) = 1
    THROW 50103, N'Der Login ist sysadmin und würde alle Kunden sehen. Für den Kundenzugriff in der Cloud nicht zulässig.', 1;

-- ------------------------------------------------------------
-- 1. Kunde und Login-Zuordnung
-- ------------------------------------------------------------
DECLARE @CustomerId INT = (SELECT CustomerId FROM mailrelay.Customer WHERE ShortName = @ShortName);
IF @CustomerId IS NULL
BEGIN
    INSERT INTO mailrelay.Customer (Name, ShortName) VALUES (@CustomerName, @ShortName);
    SET @CustomerId = CAST(SCOPE_IDENTITY() AS INT);
    PRINT N'Kunde ' + @ShortName + N' angelegt (Id ' + CAST(@CustomerId AS NVARCHAR(10)) + N').';
END
ELSE
    UPDATE mailrelay.Customer SET Name = @CustomerName WHERE CustomerId = @CustomerId;

IF EXISTS (SELECT 1 FROM mailrelay.CustomerLogin WHERE LoginName = @Login AND CustomerId <> @CustomerId)
    THROW 50104, N'Der Login ist bereits einem anderen Kunden zugeordnet.', 1;

IF NOT EXISTS (SELECT 1 FROM mailrelay.CustomerLogin WHERE LoginName = @Login)
    INSERT INTO mailrelay.CustomerLogin (CustomerId, LoginName) VALUES (@CustomerId, @Login);

-- ------------------------------------------------------------
-- 2. Datenbank-Benutzer und Rechte in der Relay-Datenbank
-- ------------------------------------------------------------
DECLARE @UserName SYSNAME = (SELECT name FROM sys.database_principals WHERE sid = SUSER_SID(@Login));
IF @UserName IS NULL
BEGIN
    SET @UserName = @Login;
    EXEC (N'CREATE USER [' + @UserName + N'] FOR LOGIN [' + @Login + N']');
    PRINT N'Datenbank-Benutzer ' + @UserName + N' angelegt.';
END

IF @IsCloud = 1
BEGIN
    IF IS_ROLEMEMBER(N'db_owner', @UserName) = 1 OR IS_ROLEMEMBER(N'mailrelay_service', @UserName) = 1
        THROW 50105, N'Der Login ist in der Relay-Datenbank db_owner bzw. Mitglied von mailrelay_service und würde alle Kunden sehen. Bitte die Rolle entfernen.', 1;
END
ELSE IF IS_ROLEMEMBER(N'db_owner', @UserName) = 1
    PRINT N'Hinweis: Der Login ist db_owner dieser Datenbank und sieht alle Relay-Daten (bei einer Einzelinstallation gewollt).';

EXEC (N'GRANT SELECT, EXECUTE ON SCHEMA::[mailrelay_kunde] TO [' + @UserName + N']');

-- ------------------------------------------------------------
-- 3. Synonyme in der NextGen-Datenbank (Schema mailrelay_ng)
-- ------------------------------------------------------------
DECLARE @exec NVARCHAR(300) = QUOTENAME(@NextGenDb) + N'.sys.sp_executesql';
EXEC @exec N'IF SCHEMA_ID(N''mailrelay_ng'') IS NULL EXEC (N''CREATE SCHEMA [mailrelay_ng] AUTHORIZATION [dbo]'');';

DECLARE @objects TABLE (Name SYSNAME);
INSERT INTO @objects (Name) VALUES
    (N'Protokoll'), (N'Verlauf'), (N'Mail'), (N'Profile'), (N'ErlaubteAbsender'), (N'SmtpBenutzer'), (N'Testauftraege'),
    (N'NeuSenden'), (N'Abbrechen'), (N'ProfilSpeichern'), (N'SecretSetzen'), (N'TestmailAnfordern');

DECLARE @name SYSNAME, @sql NVARCHAR(MAX);
DECLARE objects CURSOR LOCAL FAST_FORWARD FOR SELECT Name FROM @objects;
OPEN objects;
FETCH NEXT FROM objects INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'IF OBJECT_ID(N''mailrelay_ng.rk_' + @name + N''', N''SN'') IS NOT NULL DROP SYNONYM [mailrelay_ng].[rk_' + @name + N'];'
             + N'CREATE SYNONYM [mailrelay_ng].[rk_' + @name + N'] FOR ' + QUOTENAME(@RelayDb) + N'.[mailrelay_kunde].' + QUOTENAME(@name) + N';';
    EXEC @exec @sql;
    FETCH NEXT FROM objects INTO @name;
END
CLOSE objects;
DEALLOCATE objects;

-- Rechte auf die Synonyme und Prozeduren in der NextGen-Datenbank (nötig, falls der Login dort nicht db_owner ist)
SET @sql = N'DECLARE @u SYSNAME = (SELECT name FROM sys.database_principals WHERE sid = SUSER_SID(@login));'
         + N'IF @u IS NOT NULL EXEC (N''GRANT SELECT, EXECUTE ON SCHEMA::[mailrelay_ng] TO ['' + @u + N'']'');'
         + N'ELSE PRINT N''Hinweis: Der Login hat in der NextGen-Datenbank keinen eigenen Benutzer (z.B. Zugriff über eine Windows-Gruppe). Rechte auf das Schema mailrelay_ng bitte der Gruppe geben.'';';
EXEC @exec @sql, N'@login SYSNAME', @login = @Login;

PRINT N'';
PRINT N'Kunde ' + @ShortName + N' eingerichtet (' + CASE WHEN @IsCloud = 1 THEN N'Cloud' ELSE N'Einzelinstallation' END + N').';
PRINT N'Nächste Schritte:';
PRINT N'  1. NextGen-Paket.sql in der Datenbank ' + @NextGenDb + N' ausführen.';
PRINT N'  2. In der Relay-Weboberfläche die Profile dem Kunden zuordnen.';
