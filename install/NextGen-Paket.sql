-- ============================================================
-- Vemas.MailRelay - NextGen-Paket "Mail-Relay"
--
-- Ausführen: in SSMS, verbunden mit der NEXTGEN-DATENBANK des Kunden,
--            nachdem Add-Customer.sql die Synonyme (Schema mailrelay_ng, rk_*) angelegt hat.
-- Das Skript ist wiederholbar und für Cloud und Einzelinstallation identisch.
--
-- Inhalt:
--   * Prozeduren mailrelay_ng.* für Datasources und Aktionen
--   * Datasources MAILRELAY_*, Spalten, Parameter, Aktionen
--   * Formulare MAILRELAY.PROFIL, MAILRELAY.SECRET, MAILRELAY.TESTMAIL
--   * NavigatorFunctions, FunctionFolder "MailRelay", Navigator-Eintrag
--   * Übersetzungen Deutsch/Englisch (Präfix MAILRELAY.)
-- Sichtbar nur für NextGen-Administratoren (OpenPermission "AdministrateNextGen").
-- ============================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- Bei fehlender Voraussetzung werden alle folgenden Batches nicht ausgeführt (SET NOEXEC ON).
IF OBJECT_ID(N'vngSys.Datasources', N'U') IS NULL
BEGIN
    RAISERROR(N'Dies ist keine NextGen-Datenbank. Skript wird nicht ausgeführt.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF OBJECT_ID(N'mailrelay_ng.rk_Protokoll', N'SN') IS NULL
BEGIN
    RAISERROR(N'Synonyme fehlen: zuerst Add-Customer.sql in der Datenbank des Relays ausführen. Skript wird nicht ausgeführt.', 16, 1);
    SET NOEXEC ON;
END
GO

-- ============================================================
-- 1. Prozeduren für die Datasources (NextGen übergibt @currentagent automatisch)
-- ============================================================
CREATE OR ALTER PROCEDURE mailrelay_ng.Protokoll
    @currentagent NVARCHAR(100) = NULL,
    @Tage         INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ab DATETIME2(3) = DATEADD(DAY, -ISNULL(NULLIF(@Tage, 0), 30), SYSUTCDATETIME());

    SELECT MessageId AS _ObjID,
           MessageId, Eingang, StatusText AS Status, Status AS StatusCode,
           Absender, Empfaenger, Betreff,
           CAST(GroesseBytes / 1024.0 AS DECIMAL(12, 1)) AS GroesseKB,
           Versuche, Gesendet, NaechsterVersuch, LetzterFehler,
           Profil, SmtpBenutzer, InhaltVorhanden
      FROM mailrelay_ng.rk_Protokoll
     WHERE EingangUtc >= @ab
     ORDER BY MessageId DESC;
END
GO

CREATE OR ALTER PROCEDURE mailrelay_ng.Verlauf
    @currentagent NVARCHAR(100) = NULL,
    @MessageId    BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT AttemptId AS _ObjID,
           Zeitpunkt, ArtText AS Art,
           CASE Erfolg WHEN 1 THEN N'OK' WHEN 0 THEN N'Fehler' END AS Ergebnis,
           HttpStatus, Fehler, Benutzer, RequestId
      FROM mailrelay_ng.rk_Verlauf
     WHERE MessageId = @MessageId
     ORDER BY AttemptId DESC;
END
GO

CREATE OR ALTER PROCEDURE mailrelay_ng.Mail
    @currentagent NVARCHAR(100) = NULL,
    @MessageId    BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT MessageId AS _ObjID,
           Eingang, StatusText AS Status, Absender, An, Cc, EmpfaengerSmtp, AntwortAn, Betreff, Anhaenge, Text
      FROM mailrelay_ng.rk_Mail
     WHERE MessageId = @MessageId;
END
GO

CREATE OR ALTER PROCEDURE mailrelay_ng.Profile
    @currentagent NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ProfileId AS _ObjID,
           ProfileId, Name, ModusText AS Modus, SendenAls, StandardPostfach, TenantId, ClientId,
           CASE WHEN SecretWirdVerarbeitet = 1 THEN N'wird übernommen'
                WHEN SecretHinterlegt = 1 THEN N'hinterlegt'
                ELSE N'fehlt' END AS Secret,
           SecretGueltigBis, ErlaubteAbsender, Aktiv
      FROM mailrelay_ng.rk_Profile
     ORDER BY Name;
END
GO

CREATE OR ALTER PROCEDURE mailrelay_ng.SmtpBenutzer
    @currentagent NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SmtpUserId AS _ObjID, Login, Aktiv, LetzteAnmeldung, Profil
      FROM mailrelay_ng.rk_SmtpBenutzer
     ORDER BY Login;
END
GO

CREATE OR ALTER PROCEDURE mailrelay_ng.Testauftraege
    @currentagent NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (200) TestMailRequestId AS _ObjID,
           Angefordert, Profil, Empfaenger, AngefordertVon, MessageId, StatusText AS Status, Fehler
      FROM mailrelay_ng.rk_Testauftraege
     ORDER BY TestMailRequestId DESC;
END
GO

-- ============================================================
-- 2. Prozeduren für die Aktionen (Aufruf über formapicall/GenericExecuteSP)
-- ============================================================
CREATE OR ALTER PROCEDURE mailrelay_ng.NeuSenden
    @MessageId BIGINT,
    @Benutzer  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC mailrelay_ng.rk_NeuSenden @MessageId = @MessageId, @Benutzer = @Benutzer;
END
GO

CREATE OR ALTER PROCEDURE mailrelay_ng.Abbrechen
    @MessageId BIGINT,
    @Benutzer  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC mailrelay_ng.rk_Abbrechen @MessageId = @MessageId, @Benutzer = @Benutzer;
END
GO

CREATE OR ALTER PROCEDURE mailrelay_ng.ProfilSpeichern
    @ProfileId        INT,
    @Name             NVARCHAR(100),
    @TenantId         NVARCHAR(100),
    @ClientId         NVARCHAR(100),
    @SendenAls        BIT = 0,
    @StandardPostfach NVARCHAR(320),
    @ErlaubteAbsender NVARCHAR(MAX) = NULL,
    @Benutzer         NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC mailrelay_ng.rk_ProfilSpeichern @ProfileId = @ProfileId, @Name = @Name, @TenantId = @TenantId, @ClientId = @ClientId,
         @SendenAls = @SendenAls, @StandardPostfach = @StandardPostfach, @ErlaubteAbsender = @ErlaubteAbsender, @Benutzer = @Benutzer;
END
GO

CREATE OR ALTER PROCEDURE mailrelay_ng.SecretSetzen
    @ProfileId  INT,
    @Secret     NVARCHAR(500),
    @GueltigBis DATE = NULL,
    @Benutzer   NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC mailrelay_ng.rk_SecretSetzen @ProfileId = @ProfileId, @Secret = @Secret, @GueltigBis = @GueltigBis, @Benutzer = @Benutzer;
END
GO

CREATE OR ALTER PROCEDURE mailrelay_ng.TestmailAnfordern
    @ProfileId  INT,
    @Empfaenger NVARCHAR(320),
    @Benutzer   NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC mailrelay_ng.rk_TestmailAnfordern @ProfileId = @ProfileId, @Empfaenger = @Empfaenger, @Benutzer = @Benutzer;
END
GO

-- ============================================================
-- 3. NextGen-Metadaten
-- ============================================================
DECLARE @ZielNavigator NVARCHAR(100) = N'Default';   -- Navigator, in dem der Eintrag "Mail-Relay" erscheint
DECLARE @NavOrderId    INT           = 900;          -- Position im Navigator

DECLARE @Security NVARCHAR(200) = N'{"OpenPermission":"AdministrateNextGen"}';
DECLARE @Grid NVARCHAR(MAX) = N'{"PrimaryKey":["_objid"],"TreeAutoExpandAll":true,"CommandColumnWidth":"45px","GroupPanelVisible":true,"CardViewOptions":{"PageSize":{"Grouped":5,"Ungrouped":10}},"ShowPreviewRow":true,"AllowColumnDragging":true,"AllowFixing":true,"SortingMode":"multiple","ColumnChooserMode":"select","AllowFiltering":true,"ScrollingMode":"standard","SelectionMode":"single","ShowCheckBoxesMode":"none","FocusedRowEnabled":true,"SelectAllMode":"allPages","Paging":true,"PageSize":50,"PageSizeSelectorVisible":true,"PageSizes":[10,25,50,100],"PageInfoVisible":true,"PageNavigationButtonsVisible":true,"RowAlternation":true,"EnableLayouts":true,"ListPageMode":"nextButton","showRowLines":true,"showColumnLines":true,"AllowFullscreen":false}';
DECLARE @Props NVARCHAR(MAX) = N'{"ChartSettings":{},"SimpleListSettings":{},"DrillDownSettings":{"initiallyClosed":false,"showAlways":false},"CacheMethod":"FileSystem","ChartBindingSettings":{},"LegacyModeSettings":{"IgnoreNullAllParameters":false},"ReloadDataSettings":{"ReloadOnActivation":true},"RemoteOperations":false}';
DECLARE @ColDefault NVARCHAR(MAX) = N'{"AllowGrouping":true,"AllowSorting":true,"AllowFixing":true,"AutoExpandGroup":false,"isPreviewColumn":false,"scrollPreviewColumn":false,"applyChangesToSelection":false,"isBand":false}';
DECLARE @ColPreview NVARCHAR(MAX) = N'{"AllowGrouping":false,"AllowSorting":false,"AllowFixing":false,"AutoExpandGroup":false,"isPreviewColumn":true,"scrollPreviewColumn":false,"applyChangesToSelection":false,"isBand":false}';
DECLARE @RowAction NVARCHAR(MAX) = N'{"IsRowAction":true,"IsDefaultAction":false,"ShowCaptionWhenSeparate":false,"MoreOptionsPriority":0,"_useDynamicPositioning":false,"Selector":"Single"}';
DECLARE @DefaultAction NVARCHAR(MAX) = N'{"IsRowAction":true,"IsDefaultAction":true,"ShowCaptionWhenSeparate":false,"MoreOptionsPriority":0,"_useDynamicPositioning":false,"Selector":"Single"}';
DECLARE @DialogAction NVARCHAR(MAX) = N'{"EnabledOnFormValid":false,"ButtonPosition":"DialogAction","MoreOptionsPriority":-1}';
DECLARE @FormParams NVARCHAR(MAX) = N'{"Notification":false,"FullHeight":false,"SearchEnabled":false,"SkipEntityObjectLock":false,"Chat":false,"GenericActions":[]}';
DECLARE @UI NVARCHAR(MAX) = N'{"DevOnly":false,"Hidden":false,"ResponsiveOptions":{"VisibleWith":{},"HiddenWith":{}}}';

BEGIN TRANSACTION;

-- ---------- Altbestand entfernen (wiederholbar) ----------
DELETE FROM vngSys.DatasourceActions    WHERE DatasourceName LIKE N'MAILRELAY[_]%';
DELETE FROM vngSys.DatasourceColumns    WHERE DatasourceName LIKE N'MAILRELAY[_]%';
DELETE FROM vngSys.DatasourceParameters WHERE DatasourceName LIKE N'MAILRELAY[_]%';
DELETE FROM vngSys.Datasources          WHERE DatasourceName LIKE N'MAILRELAY[_]%';
DELETE FROM vngSys.FormActions          WHERE FormName LIKE N'MAILRELAY.%';
DELETE FROM vngSys.FormElements         WHERE FormName LIKE N'MAILRELAY.%';
DELETE FROM vngSys.Forms                WHERE FormName LIKE N'MAILRELAY.%';
DELETE FROM vngSys.NavigatorItems       WHERE ItemName = N'ItemMailRelay';
DELETE FROM vngSys.NavigatorFunctions   WHERE FunctionName LIKE N'MailRelay%' OR FunctionName = N'FunctionFolderMailRelay';
DELETE i FROM vngSys.FunctionFolderItems  i JOIN vngSys.FunctionFolders f ON f.Guid = i.FunctionFolderGuid WHERE f.FolderName = N'MailRelay';
DELETE g FROM vngSys.FunctionFolderGroups g JOIN vngSys.FunctionFolders f ON f.Guid = g.FunctionFolderGuid WHERE f.FolderName = N'MailRelay';
DELETE FROM vngSys.FunctionFolders      WHERE FolderName = N'MailRelay';

-- ---------- Datasources ----------
INSERT INTO vngSys.Datasources (DatasourceName, SPName, Type, SortGroupParameters, DataSourceProperties, CacheBehavior, SecurityParameters, Comment)
VALUES
    (N'MAILRELAY_PROTOKOLL',    N'mailrelay_ng.Protokoll',     N'Datagrid', @Grid, @Props, 0, @Security, N'Vemas.MailRelay'),
    (N'MAILRELAY_VERLAUF',      N'mailrelay_ng.Verlauf',       N'Datagrid', @Grid, @Props, 0, @Security, N'Vemas.MailRelay'),
    (N'MAILRELAY_MAIL',         N'mailrelay_ng.Mail',          N'Datagrid', @Grid, @Props, 0, @Security, N'Vemas.MailRelay'),
    (N'MAILRELAY_PROFILE',      N'mailrelay_ng.Profile',       N'Datagrid', @Grid, @Props, 0, @Security, N'Vemas.MailRelay'),
    (N'MAILRELAY_SMTPBENUTZER', N'mailrelay_ng.SmtpBenutzer',  N'Datagrid', @Grid, @Props, 0, @Security, N'Vemas.MailRelay'),
    (N'MAILRELAY_TESTMAILS',    N'mailrelay_ng.Testauftraege', N'Datagrid', @Grid, @Props, 0, @Security, N'Vemas.MailRelay');

INSERT INTO vngSys.DatasourceParameters (DatasourceName, ParameterName, UIType, Caption, Required, Hidden, OrderID)
VALUES
    (N'MAILRELAY_PROTOKOLL', N'Tage',      N'numberinput', N'MAILRELAY.PARAM.TAGE',      0, 0, 1),
    (N'MAILRELAY_VERLAUF',   N'MessageId', N'textbox',     N'MAILRELAY.PARAM.MESSAGEID', 0, 1, 1),
    (N'MAILRELAY_MAIL',      N'MessageId', N'textbox',     N'MAILRELAY.PARAM.MESSAGEID', 0, 1, 1);

-- ---------- Spalten (Caption = MAILRELAY.COL.<Spalte>) ----------
INSERT INTO vngSys.DatasourceColumns (DatasourceName, ColumnName, Caption, IsVisible, OrderID, Width, EditParameters, SortGroupParameters)
SELECT d, c, N'MAILRELAY.COL.' + UPPER(c), v, o, w, N'{"ShowClearButton":false}', CASE WHEN p = 1 THEN @ColPreview ELSE @ColDefault END
  FROM (VALUES
    (N'MAILRELAY_PROTOKOLL', N'MessageId',        1,  10,  70, 0),
    (N'MAILRELAY_PROTOKOLL', N'Eingang',          1,  20, 140, 0),
    (N'MAILRELAY_PROTOKOLL', N'Status',           1,  30, 120, 0),
    (N'MAILRELAY_PROTOKOLL', N'StatusCode',       0,  35,  -1, 0),
    (N'MAILRELAY_PROTOKOLL', N'Absender',         1,  40, 200, 0),
    (N'MAILRELAY_PROTOKOLL', N'Empfaenger',       1,  50, 220, 0),
    (N'MAILRELAY_PROTOKOLL', N'Betreff',          1,  60,  -1, 0),
    (N'MAILRELAY_PROTOKOLL', N'GroesseKB',        1,  70,  90, 0),
    (N'MAILRELAY_PROTOKOLL', N'Versuche',         1,  80,  80, 0),
    (N'MAILRELAY_PROTOKOLL', N'Gesendet',         1,  90, 140, 0),
    (N'MAILRELAY_PROTOKOLL', N'NaechsterVersuch', 0, 100, 140, 0),
    (N'MAILRELAY_PROTOKOLL', N'LetzterFehler',    1, 110, 250, 0),
    (N'MAILRELAY_PROTOKOLL', N'Profil',           0, 120, 150, 0),
    (N'MAILRELAY_PROTOKOLL', N'SmtpBenutzer',     0, 130, 150, 0),
    (N'MAILRELAY_PROTOKOLL', N'InhaltVorhanden',  0, 140,  90, 0),
    (N'MAILRELAY_VERLAUF',   N'Zeitpunkt',        1,  10, 140, 0),
    (N'MAILRELAY_VERLAUF',   N'Art',              1,  20, 110, 0),
    (N'MAILRELAY_VERLAUF',   N'Ergebnis',         1,  30,  80, 0),
    (N'MAILRELAY_VERLAUF',   N'HttpStatus',       1,  40,  70, 0),
    (N'MAILRELAY_VERLAUF',   N'Fehler',           1,  50,  -1, 0),
    (N'MAILRELAY_VERLAUF',   N'Benutzer',         1,  60, 220, 0),
    (N'MAILRELAY_VERLAUF',   N'RequestId',        0,  70, 200, 0),
    (N'MAILRELAY_MAIL',      N'Eingang',          1,  10, 140, 0),
    (N'MAILRELAY_MAIL',      N'Status',           1,  20, 110, 0),
    (N'MAILRELAY_MAIL',      N'Absender',         1,  30, 180, 0),
    (N'MAILRELAY_MAIL',      N'An',               1,  40, 200, 0),
    (N'MAILRELAY_MAIL',      N'Cc',               1,  50, 150, 0),
    (N'MAILRELAY_MAIL',      N'EmpfaengerSmtp',   0,  60, 200, 0),
    (N'MAILRELAY_MAIL',      N'AntwortAn',        0,  70, 150, 0),
    (N'MAILRELAY_MAIL',      N'Betreff',          1,  80,  -1, 0),
    (N'MAILRELAY_MAIL',      N'Anhaenge',         1,  90, 200, 0),
    (N'MAILRELAY_MAIL',      N'Text',             1, 100,  -1, 1),
    (N'MAILRELAY_PROFILE',   N'ProfileId',        0,  10,  70, 0),
    (N'MAILRELAY_PROFILE',   N'Name',             1,  20, 180, 0),
    (N'MAILRELAY_PROFILE',   N'Modus',            1,  30, 130, 0),
    (N'MAILRELAY_PROFILE',   N'SendenAls',        0,  35,  -1, 0),
    (N'MAILRELAY_PROFILE',   N'StandardPostfach', 1,  40, 200, 0),
    (N'MAILRELAY_PROFILE',   N'TenantId',         1,  50, 200, 0),
    (N'MAILRELAY_PROFILE',   N'ClientId',         0,  60, 200, 0),
    (N'MAILRELAY_PROFILE',   N'Secret',           1,  70, 130, 0),
    (N'MAILRELAY_PROFILE',   N'SecretGueltigBis', 1,  80, 120, 0),
    (N'MAILRELAY_PROFILE',   N'ErlaubteAbsender', 1,  90,  -1, 0),
    (N'MAILRELAY_PROFILE',   N'Aktiv',            1, 100,  70, 0),
    (N'MAILRELAY_SMTPBENUTZER', N'Login',           1, 10, 200, 0),
    (N'MAILRELAY_SMTPBENUTZER', N'Aktiv',           1, 20,  70, 0),
    (N'MAILRELAY_SMTPBENUTZER', N'LetzteAnmeldung', 1, 30, 150, 0),
    (N'MAILRELAY_SMTPBENUTZER', N'Profil',          1, 40,  -1, 0),
    (N'MAILRELAY_TESTMAILS', N'Angefordert',      1,  10, 140, 0),
    (N'MAILRELAY_TESTMAILS', N'Profil',           1,  20, 150, 0),
    (N'MAILRELAY_TESTMAILS', N'Empfaenger',       1,  30, 200, 0),
    (N'MAILRELAY_TESTMAILS', N'AngefordertVon',   1,  40, 220, 0),
    (N'MAILRELAY_TESTMAILS', N'MessageId',        1,  50,  70, 0),
    (N'MAILRELAY_TESTMAILS', N'Status',           1,  60, 110, 0),
    (N'MAILRELAY_TESTMAILS', N'Fehler',           1,  70,  -1, 0)
  ) x (d, c, v, o, w, p);

-- ---------- Aktionen im Protokoll ----------
DECLARE @ApiPrefix NVARCHAR(200) = N'Options[Caption=YES].Commands[Command=ApiCall].';

INSERT INTO vngSys.DatasourceActions (DatasourceName, ActionName, Caption, Icon, Command, CommandParameters, PositionParameters)
VALUES
(N'MAILRELAY_PROTOKOLL', N'ANZEIGEN', N'MAILRELAY.ACTION.ANZEIGEN', N'SEARCH',
 N'{"ResultType":"Command","Command":"OpenReport","DatasourceName":"MAILRELAY_MAIL","OpenInDialog":true,"DialogWidth":"lg","Params":[{"Name":"MessageId","Value":null}],"IgnoreSavedParameters":true}',
 N'[{"Parameter":"Params[Name=MessageId].Value","ColumnName":"MessageId","Required":false}]',
 @DefaultAction),
(N'MAILRELAY_PROTOKOLL', N'VERLAUF', N'MAILRELAY.ACTION.VERLAUF', N'HISTORY',
 N'{"ResultType":"Command","Command":"OpenReport","DatasourceName":"MAILRELAY_VERLAUF","OpenInDialog":true,"DialogWidth":"lg","Params":[{"Name":"MessageId","Value":null}],"IgnoreSavedParameters":true}',
 N'[{"Parameter":"Params[Name=MessageId].Value","ColumnName":"MessageId","Required":false}]',
 @RowAction),
(N'MAILRELAY_PROTOKOLL', N'NEUSENDEN', N'MAILRELAY.ACTION.NEUSENDEN', N'REDO',
 N'{"ResultType":"Command","Command":"Decision","Title":"MAILRELAY.CONFIRM.TITLE","Message":"MAILRELAY.CONFIRM.NEUSENDEN","Options":[{"Caption":"YES","Icon":"check","ShowInFooter":true,"Commands":[{"ResultType":"Command","Command":"ApiCall","EndPoint":"formapicall/GenericExecuteSP","Body":{"SPName":"mailrelay_ng.NeuSenden","Parameters":[{"Name":"MessageId","Value":null},{"Name":"Benutzer","Value":null}],"RefreshAfterExecute":true},"CallerInstanceName":null}]},{"Caption":"NO","Icon":"times","ShowInFooter":true}]}',
 N'[{"Parameter":"' + @ApiPrefix + N'Body.Parameters[Name=MessageId].Value","ColumnName":"MessageId","Required":false},{"Parameter":"' + @ApiPrefix + N'Body.Parameters[Name=Benutzer].Value","KeyValue":"currentUser","Required":false},{"Parameter":"' + @ApiPrefix + N'CallerInstanceName","KeyValue":"FormInstanceName","Required":false}]',
 N'{"IsRowAction":true,"IsDefaultAction":false,"ShowCaptionWhenSeparate":false,"MoreOptionsPriority":0,"_useDynamicPositioning":false,"Selector":"Single","SelectorExpr":"$boolean(data.inhaltvorhanden) and data.statuscode in [\"Sent\",\"Failed\",\"Cancelled\"]"}'),
(N'MAILRELAY_PROTOKOLL', N'ABBRECHEN', N'MAILRELAY.ACTION.ABBRECHEN', N'STOP',
 N'{"ResultType":"Command","Command":"Decision","Title":"MAILRELAY.CONFIRM.TITLE","Message":"MAILRELAY.CONFIRM.ABBRECHEN","Options":[{"Caption":"YES","Icon":"check","ShowInFooter":true,"Commands":[{"ResultType":"Command","Command":"ApiCall","EndPoint":"formapicall/GenericExecuteSP","Body":{"SPName":"mailrelay_ng.Abbrechen","Parameters":[{"Name":"MessageId","Value":null},{"Name":"Benutzer","Value":null}],"RefreshAfterExecute":true},"CallerInstanceName":null}]},{"Caption":"NO","Icon":"times","ShowInFooter":true}]}',
 N'[{"Parameter":"' + @ApiPrefix + N'Body.Parameters[Name=MessageId].Value","ColumnName":"MessageId","Required":false},{"Parameter":"' + @ApiPrefix + N'Body.Parameters[Name=Benutzer].Value","KeyValue":"currentUser","Required":false},{"Parameter":"' + @ApiPrefix + N'CallerInstanceName","KeyValue":"FormInstanceName","Required":false}]',
 N'{"IsRowAction":true,"IsDefaultAction":false,"ShowCaptionWhenSeparate":false,"MoreOptionsPriority":0,"_useDynamicPositioning":false,"Selector":"Single","SelectorExpr":"data.statuscode in [\"Queued\",\"Retry\"]"}');

-- ---------- Aktionen bei den Profilen ----------
INSERT INTO vngSys.DatasourceActions (DatasourceName, ActionName, Caption, Icon, Command, CommandParameters, PositionParameters)
VALUES
(N'MAILRELAY_PROFILE', N'BEARBEITEN', N'MAILRELAY.ACTION.BEARBEITEN', N'EDIT',
 N'{"ResultType":"Command","Command":"OpenForm","FormName":"MAILRELAY.PROFIL","OpenInDialog":true,"DialogWidth":"md","IsNew":true,"Defaults":{"profileid":null,"name":null,"tenantid":null,"clientid":null,"sendenals":null,"standardpostfach":null,"erlaubteabsender":null},"CallerInstanceName":null}',
 N'[{"Parameter":"Defaults.profileid","ColumnName":"ProfileId"},{"Parameter":"Defaults.name","ColumnName":"Name"},{"Parameter":"Defaults.tenantid","ColumnName":"TenantId"},{"Parameter":"Defaults.clientid","ColumnName":"ClientId"},{"Parameter":"Defaults.sendenals","ColumnName":"SendenAls"},{"Parameter":"Defaults.standardpostfach","ColumnName":"StandardPostfach"},{"Parameter":"Defaults.erlaubteabsender","ColumnName":"ErlaubteAbsender"},{"Parameter":"CallerInstanceName","KeyValue":"FormInstanceName"}]',
 @DefaultAction),
(N'MAILRELAY_PROFILE', N'SECRET', N'MAILRELAY.ACTION.SECRET', N'SYSLOCK',
 N'{"ResultType":"Command","Command":"OpenForm","FormName":"MAILRELAY.SECRET","OpenInDialog":true,"DialogWidth":"md","IsNew":true,"Defaults":{"profileid":null,"name":null,"secret":null,"gueltigbis":null},"CallerInstanceName":null}',
 N'[{"Parameter":"Defaults.profileid","ColumnName":"ProfileId"},{"Parameter":"Defaults.name","ColumnName":"Name"},{"Parameter":"Defaults.gueltigbis","ColumnName":"SecretGueltigBis"},{"Parameter":"CallerInstanceName","KeyValue":"FormInstanceName"}]',
 @RowAction),
(N'MAILRELAY_PROFILE', N'TESTMAIL', N'MAILRELAY.ACTION.TESTMAIL', N'PAPER-PLANE',
 N'{"ResultType":"Command","Command":"OpenForm","FormName":"MAILRELAY.TESTMAIL","OpenInDialog":true,"DialogWidth":"md","IsNew":true,"Defaults":{"profileid":null,"name":null,"empfaenger":null},"CallerInstanceName":null}',
 N'[{"Parameter":"Defaults.profileid","ColumnName":"ProfileId"},{"Parameter":"Defaults.name","ColumnName":"Name"},{"Parameter":"CallerInstanceName","KeyValue":"FormInstanceName"}]',
 @RowAction);

-- ---------- Formulare (ohne Entität, Felder binden an Formulardaten) ----------
DECLARE @TextBox  NVARCHAR(MAX) = N'{"mode":"text","showClearButton":false,"emptyValueToNull":false,"readOnly":false,"hidden":false,"preventRendering":false}';
DECLARE @Password NVARCHAR(MAX) = N'{"mode":"password","showClearButton":false,"emptyValueToNull":false,"readOnly":false,"hidden":false,"preventRendering":false}';
DECLARE @ReadOnly NVARCHAR(MAX) = N'{"mode":"text","showClearButton":false,"emptyValueToNull":false,"readOnly":true,"hidden":false,"preventRendering":false}';
DECLARE @Switch   NVARCHAR(MAX) = N'{"inlineLabel":false,"defaultValue":false,"skipEventHandlers":false,"readOnly":false,"hidden":false,"preventRendering":false}';
DECLARE @TextArea NVARCHAR(MAX) = N'{"height":120,"showClearButton":false,"emptyValueToNull":false,"readOnly":false,"hidden":false,"preventRendering":false,"helptext":"MAILRELAY.HINT.ERLAUBTEABSENDER"}';
DECLARE @DateBox  NVARCHAR(MAX) = N'{"native":false,"type":"Date","showClearButton":true,"emptyValueToNull":true,"readOnly":false,"hidden":false,"preventRendering":false}';

DECLARE @p1 INT = vngSys.GetNewElementID(), @p2 INT = vngSys.GetNewElementID(), @p3 INT = vngSys.GetNewElementID(),
        @p4 INT = vngSys.GetNewElementID(), @p5 INT = vngSys.GetNewElementID(), @p6 INT = vngSys.GetNewElementID();
DECLARE @s1 INT = vngSys.GetNewElementID(), @s2 INT = vngSys.GetNewElementID(), @s3 INT = vngSys.GetNewElementID();
DECLARE @t1 INT = vngSys.GetNewElementID(), @t2 INT = vngSys.GetNewElementID();

INSERT INTO vngSys.Forms (FormName, Caption, ChildFormElements, FormParameters, SecurityParameters, Comment)
VALUES
    (N'MAILRELAY.PROFIL',   N'MAILRELAY.FORM.PROFIL',
     CONCAT(N'[', @p1, N',', @p2, N',', @p3, N',', @p4, N',', @p5, N',', @p6, N']'), @FormParams, @Security, N'Vemas.MailRelay'),
    (N'MAILRELAY.SECRET',   N'MAILRELAY.FORM.SECRET',
     CONCAT(N'[', @s1, N',', @s2, N',', @s3, N']'), @FormParams, @Security, N'Vemas.MailRelay'),
    (N'MAILRELAY.TESTMAIL', N'MAILRELAY.FORM.TESTMAIL',
     CONCAT(N'[', @t1, N',', @t2, N']'), @FormParams, @Security, N'Vemas.MailRelay');

INSERT INTO vngSys.FormElements (FormName, ElementID, ElementName, ElementType, Caption, EntityField, ElementProperties, UIProperties)
VALUES
    (N'MAILRELAY.PROFIL',   @p1, N'name',             N'textbox',  N'MAILRELAY.COL.NAME',             N'name',             @TextBox,  @UI),
    (N'MAILRELAY.PROFIL',   @p2, N'tenantid',         N'textbox',  N'MAILRELAY.COL.TENANTID',         N'tenantid',         @TextBox,  @UI),
    (N'MAILRELAY.PROFIL',   @p3, N'clientid',         N'textbox',  N'MAILRELAY.COL.CLIENTID',         N'clientid',         @TextBox,  @UI),
    (N'MAILRELAY.PROFIL',   @p4, N'standardpostfach', N'textbox',  N'MAILRELAY.COL.STANDARDPOSTFACH', N'standardpostfach', @TextBox,  @UI),
    (N'MAILRELAY.PROFIL',   @p5, N'sendenals',        N'switch',   N'MAILRELAY.COL.SENDENALS',        N'sendenals',        @Switch,   @UI),
    (N'MAILRELAY.PROFIL',   @p6, N'erlaubteabsender', N'textarea', N'MAILRELAY.COL.ERLAUBTEABSENDER', N'erlaubteabsender', @TextArea, @UI),
    (N'MAILRELAY.SECRET',   @s1, N'name',             N'textbox',  N'MAILRELAY.COL.NAME',             N'name',             @ReadOnly, @UI),
    (N'MAILRELAY.SECRET',   @s2, N'secret',           N'textbox',  N'MAILRELAY.FIELD.NEUESSECRET',    N'secret',           @Password, @UI),
    (N'MAILRELAY.SECRET',   @s3, N'gueltigbis',       N'datebox',  N'MAILRELAY.COL.SECRETGUELTIGBIS', N'gueltigbis',       @DateBox,  @UI),
    (N'MAILRELAY.TESTMAIL', @t1, N'name',             N'textbox',  N'MAILRELAY.COL.NAME',             N'name',             @ReadOnly, @UI),
    (N'MAILRELAY.TESTMAIL', @t2, N'empfaenger',       N'textbox',  N'MAILRELAY.FIELD.EMPFAENGER',     N'empfaenger',       @TextBox,  @UI);

-- Formularaktionen: Prozedur aufrufen, aufrufende Liste aktualisieren, Dialog schließen
INSERT INTO vngSys.FormActions (FormName, ActionName, Caption, Icon, Command, CommandParameters, PositionParameters)
VALUES
(N'MAILRELAY.PROFIL', N'SPEICHERN', N'SAVE', N'CHECK',
 N'[{"ResultType":"Command","Command":"ApiCall","EndPoint":"formapicall/GenericExecuteSP","Body":{"SPName":"mailrelay_ng.ProfilSpeichern","Parameters":[{"Name":"ProfileId","Value":null},{"Name":"Name","Value":null},{"Name":"TenantId","Value":null},{"Name":"ClientId","Value":null},{"Name":"SendenAls","Value":null},{"Name":"StandardPostfach","Value":null},{"Name":"ErlaubteAbsender","Value":null},{"Name":"Benutzer","Value":null}],"RefreshAfterExecute":true},"CallerInstanceName":null},{"ResultType":"Command","Command":"Close","InstanceName":null}]',
 N'[{"Parameter":"Body.Parameters[Name=ProfileId].Value","DataField":"profileid","Relative":false},{"Parameter":"Body.Parameters[Name=Name].Value","DataField":"name","Relative":false},{"Parameter":"Body.Parameters[Name=TenantId].Value","DataField":"tenantid","Relative":false},{"Parameter":"Body.Parameters[Name=ClientId].Value","DataField":"clientid","Relative":false},{"Parameter":"Body.Parameters[Name=SendenAls].Value","DataField":"sendenals","Relative":false},{"Parameter":"Body.Parameters[Name=StandardPostfach].Value","DataField":"standardpostfach","Relative":false},{"Parameter":"Body.Parameters[Name=ErlaubteAbsender].Value","DataField":"erlaubteabsender","Relative":false},{"Parameter":"Body.Parameters[Name=Benutzer].Value","KeyValue":"currentUser"},{"Parameter":"CallerInstanceName","KeyValue":"CallerInstanceName"},{"Parameter":"InstanceName","KeyValue":"FormInstanceName"}]',
 @DialogAction),
(N'MAILRELAY.SECRET', N'SPEICHERN', N'SAVE', N'CHECK',
 N'[{"ResultType":"Command","Command":"ApiCall","EndPoint":"formapicall/GenericExecuteSP","Body":{"SPName":"mailrelay_ng.SecretSetzen","Parameters":[{"Name":"ProfileId","Value":null},{"Name":"Secret","Value":null},{"Name":"GueltigBis","Value":null},{"Name":"Benutzer","Value":null}],"RefreshAfterExecute":true},"CallerInstanceName":null},{"ResultType":"Command","Command":"Close","InstanceName":null}]',
 N'[{"Parameter":"Body.Parameters[Name=ProfileId].Value","DataField":"profileid","Relative":false},{"Parameter":"Body.Parameters[Name=Secret].Value","DataField":"secret","Relative":false},{"Parameter":"Body.Parameters[Name=GueltigBis].Value","DataField":"gueltigbis","Relative":false},{"Parameter":"Body.Parameters[Name=Benutzer].Value","KeyValue":"currentUser"},{"Parameter":"CallerInstanceName","KeyValue":"CallerInstanceName"},{"Parameter":"InstanceName","KeyValue":"FormInstanceName"}]',
 @DialogAction),
(N'MAILRELAY.TESTMAIL', N'SENDEN', N'MAILRELAY.ACTION.TESTMAIL', N'PAPER-PLANE',
 N'[{"ResultType":"Command","Command":"ApiCall","EndPoint":"formapicall/GenericExecuteSP","Body":{"SPName":"mailrelay_ng.TestmailAnfordern","Parameters":[{"Name":"ProfileId","Value":null},{"Name":"Empfaenger","Value":null},{"Name":"Benutzer","Value":null}],"RefreshAfterExecute":true},"CallerInstanceName":null},{"ResultType":"Command","Command":"Close","InstanceName":null}]',
 N'[{"Parameter":"Body.Parameters[Name=ProfileId].Value","DataField":"profileid","Relative":false},{"Parameter":"Body.Parameters[Name=Empfaenger].Value","DataField":"empfaenger","Relative":false},{"Parameter":"Body.Parameters[Name=Benutzer].Value","KeyValue":"currentUser"},{"Parameter":"CallerInstanceName","KeyValue":"CallerInstanceName"},{"Parameter":"InstanceName","KeyValue":"FormInstanceName"}]',
 @DialogAction);

-- ---------- Navigator-Funktionen und FunctionFolder ----------
INSERT INTO vngSys.NavigatorFunctions (FunctionName, Activated, Caption, Command, Icon, SecurityParameters, Comment)
VALUES
    (N'MailRelayProtokoll',    1, N'NAVIGATOR.MAILRELAY.PROTOKOLL',    N'{"ResultType":"Command","Command":"OpenReport","DatasourceName":"MAILRELAY_PROTOKOLL"}',    N'ENVELOPE',    @Security, N'Vemas.MailRelay'),
    (N'MailRelayTestmails',    1, N'NAVIGATOR.MAILRELAY.TESTMAILS',    N'{"ResultType":"Command","Command":"OpenReport","DatasourceName":"MAILRELAY_TESTMAILS"}',    N'PAPER-PLANE', @Security, N'Vemas.MailRelay'),
    (N'MailRelayProfile',      1, N'NAVIGATOR.MAILRELAY.PROFILE',      N'{"ResultType":"Command","Command":"OpenReport","DatasourceName":"MAILRELAY_PROFILE"}',      N'COGS',         @Security, N'Vemas.MailRelay'),
    (N'MailRelaySmtpBenutzer', 1, N'NAVIGATOR.MAILRELAY.SMTPBENUTZER', N'{"ResultType":"Command","Command":"OpenReport","DatasourceName":"MAILRELAY_SMTPBENUTZER"}', N'USERS',       @Security, N'Vemas.MailRelay'),
    (N'FunctionFolderMailRelay', 1, N'NAVIGATOR.MAILRELAY',
     N'{"ResultType":"Command","Command":"OpenForm","Entity":"SYSFUNCTIONFOLDER","ObjKey":"MailRelay","Mode":"VIEW"}', N'ENVELOPE', @Security, N'Vemas.MailRelay');

DECLARE @ffGuid UNIQUEIDENTIFIER = NEWID();
INSERT INTO vngSys.FunctionFolders (Guid, FolderName, Icon, Caption, Description, SecurityParameters, Aufnahmebenutzer, Aufnahmedatum, Aenderungsbenutzer, Aenderungsdatum)
VALUES (@ffGuid, N'MailRelay', N'ENVELOPE', N'FUNCTIONFOLDER.MAILRELAY.CAPTION', N'FUNCTIONFOLDER.MAILRELAY.DESCRIPTION', @Security, SYSTEM_USER, GETDATE(), SYSTEM_USER, GETDATE());

INSERT INTO vngSys.FunctionFolderGroups (FunctionFolderGuid, OrderId, Caption)
VALUES (@ffGuid, 1, N'MAILRELAY.GROUP.VERSAND'), (@ffGuid, 2, N'MAILRELAY.GROUP.EINRICHTUNG');

INSERT INTO vngSys.FunctionFolderItems (FunctionFolderGuid, GroupOrderId, FunctionOrderId, NavigatorFunctionKey)
VALUES (@ffGuid, 1, 1, N'MailRelayProtokoll'), (@ffGuid, 1, 2, N'MailRelayTestmails'),
       (@ffGuid, 2, 1, N'MailRelayProfile'),   (@ffGuid, 2, 2, N'MailRelaySmtpBenutzer');

INSERT INTO vngSys.NavigatorItems (NavigatorName, ItemName, Activated, IsSeperator, NavigatorFunctionName, OrderID, UIProperties, SecurityParameters)
VALUES (@ZielNavigator, N'ItemMailRelay', 1, 0, N'FunctionFolderMailRelay', @NavOrderId,
        N'{"ResponsiveOptions":{"visibleWith":{"Touch":false,"Mouse":false,"Video":false,"Audio":false},"hiddenWith":{"Touch":false,"Mouse":false,"Video":false,"Audio":false}},"DevOnly":false}', @Security);

-- ---------- Übersetzungen ----------
DECLARE @t TABLE (Placeholder NVARCHAR(400), De NVARCHAR(400), En NVARCHAR(400));
INSERT INTO @t (Placeholder, De, En) VALUES
    (N'NAVIGATOR.MAILRELAY',                 N'Mail-Relay',                N'Mail relay'),
    (N'NAVIGATOR.MAILRELAY.PROTOKOLL',       N'Mail-Relay Protokoll',      N'Mail relay log'),
    (N'NAVIGATOR.MAILRELAY.TESTMAILS',       N'Mail-Relay Testmails',      N'Mail relay test mails'),
    (N'NAVIGATOR.MAILRELAY.PROFILE',         N'Mail-Relay Profile',        N'Mail relay profiles'),
    (N'NAVIGATOR.MAILRELAY.SMTPBENUTZER',    N'Mail-Relay SMTP-Benutzer',  N'Mail relay SMTP users'),
    (N'FUNCTIONFOLDER.MAILRELAY.CAPTION',    N'Mail-Relay',                N'Mail relay'),
    (N'FUNCTIONFOLDER.MAILRELAY.DESCRIPTION',N'Mailversand über Exchange Online: Protokoll, Neu senden, Profile', N'Mail delivery via Exchange Online: log, resend, profiles'),
    (N'MAILRELAY.GROUP.VERSAND',             N'Versand',                   N'Delivery'),
    (N'MAILRELAY.GROUP.EINRICHTUNG',         N'Einrichtung',               N'Setup'),
    (N'MAILRELAY.PARAM.TAGE',                N'Zeitraum (Tage)',           N'Period (days)'),
    (N'MAILRELAY.PARAM.MESSAGEID',           N'Mail-Nr.',                  N'Mail no.'),
    (N'MAILRELAY.ACTION.ANZEIGEN',           N'Mail anzeigen',             N'Show mail'),
    (N'MAILRELAY.ACTION.VERLAUF',            N'Verlauf',                   N'History'),
    (N'MAILRELAY.ACTION.NEUSENDEN',          N'Neu senden',                N'Resend'),
    (N'MAILRELAY.ACTION.ABBRECHEN',          N'Versand abbrechen',         N'Cancel delivery'),
    (N'MAILRELAY.ACTION.BEARBEITEN',         N'Profil bearbeiten',         N'Edit profile'),
    (N'MAILRELAY.ACTION.SECRET',             N'Client Secret setzen',      N'Set client secret'),
    (N'MAILRELAY.ACTION.TESTMAIL',           N'Testmail senden',           N'Send test mail'),
    (N'MAILRELAY.CONFIRM.TITLE',             N'Mail-Relay',                N'Mail relay'),
    (N'MAILRELAY.CONFIRM.NEUSENDEN',         N'Soll die Mail erneut versendet werden?', N'Resend this mail?'),
    (N'MAILRELAY.CONFIRM.ABBRECHEN',         N'Soll der Versand dieser Mail abgebrochen werden?', N'Cancel delivery of this mail?'),
    (N'MAILRELAY.FORM.PROFIL',               N'Profil bearbeiten',         N'Edit profile'),
    (N'MAILRELAY.FORM.SECRET',               N'Client Secret setzen',      N'Set client secret'),
    (N'MAILRELAY.FORM.TESTMAIL',             N'Testmail senden',           N'Send test mail'),
    (N'MAILRELAY.FIELD.NEUESSECRET',         N'Neues Client Secret (Wert)',N'New client secret (value)'),
    (N'MAILRELAY.FIELD.EMPFAENGER',          N'Empfänger',                 N'Recipient'),
    (N'MAILRELAY.HINT.ERLAUBTEABSENDER',     N'Nur bei „Senden als“: eine Adresse oder *@domain.de pro Zeile', N'Only for "send as": one address or *@domain.com per line'),
    (N'MAILRELAY.COL.MESSAGEID',             N'Nr.',                       N'No.'),
    (N'MAILRELAY.COL.EINGANG',               N'Eingang',                   N'Received'),
    (N'MAILRELAY.COL.STATUS',                N'Status',                    N'Status'),
    (N'MAILRELAY.COL.STATUSCODE',            N'Statuscode',                N'Status code'),
    (N'MAILRELAY.COL.ABSENDER',              N'Von',                       N'From'),
    (N'MAILRELAY.COL.EMPFAENGER',            N'An',                        N'To'),
    (N'MAILRELAY.COL.BETREFF',               N'Betreff',                   N'Subject'),
    (N'MAILRELAY.COL.GROESSEKB',             N'Größe (KB)',                N'Size (KB)'),
    (N'MAILRELAY.COL.VERSUCHE',              N'Versuche',                  N'Attempts'),
    (N'MAILRELAY.COL.GESENDET',              N'Gesendet',                  N'Sent'),
    (N'MAILRELAY.COL.NAECHSTERVERSUCH',      N'Nächster Versuch',          N'Next attempt'),
    (N'MAILRELAY.COL.LETZTERFEHLER',         N'Letzter Fehler',            N'Last error'),
    (N'MAILRELAY.COL.PROFIL',                N'Profil',                    N'Profile'),
    (N'MAILRELAY.COL.SMTPBENUTZER',          N'SMTP-Benutzer',             N'SMTP user'),
    (N'MAILRELAY.COL.INHALTVORHANDEN',       N'Inhalt gespeichert',        N'Content stored'),
    (N'MAILRELAY.COL.ZEITPUNKT',             N'Zeitpunkt',                 N'Time'),
    (N'MAILRELAY.COL.ART',                   N'Aktion',                    N'Action'),
    (N'MAILRELAY.COL.ERGEBNIS',              N'Ergebnis',                  N'Result'),
    (N'MAILRELAY.COL.HTTPSTATUS',            N'HTTP',                      N'HTTP'),
    (N'MAILRELAY.COL.FEHLER',                N'Fehler',                    N'Error'),
    (N'MAILRELAY.COL.BENUTZER',              N'Benutzer',                  N'User'),
    (N'MAILRELAY.COL.REQUESTID',             N'Request-ID',                N'Request ID'),
    (N'MAILRELAY.COL.AN',                    N'An',                        N'To'),
    (N'MAILRELAY.COL.CC',                    N'Cc',                        N'Cc'),
    (N'MAILRELAY.COL.EMPFAENGERSMTP',        N'SMTP-Empfänger',            N'SMTP recipients'),
    (N'MAILRELAY.COL.ANTWORTAN',             N'Antwort an',                N'Reply to'),
    (N'MAILRELAY.COL.ANHAENGE',              N'Anhänge',                   N'Attachments'),
    (N'MAILRELAY.COL.TEXT',                  N'Text',                      N'Text'),
    (N'MAILRELAY.COL.PROFILEID',             N'Nr.',                       N'No.'),
    (N'MAILRELAY.COL.NAME',                  N'Name',                      N'Name'),
    (N'MAILRELAY.COL.MODUS',                 N'Modus',                     N'Mode'),
    (N'MAILRELAY.COL.SENDENALS',             N'Senden als (Absender aus der Mail)', N'Send as (sender from mail)'),
    (N'MAILRELAY.COL.STANDARDPOSTFACH',      N'Standard-Postfach',         N'Default mailbox'),
    (N'MAILRELAY.COL.TENANTID',              N'Tenant-ID',                 N'Tenant ID'),
    (N'MAILRELAY.COL.CLIENTID',              N'Client-ID',                 N'Client ID'),
    (N'MAILRELAY.COL.SECRET',                N'Client Secret',             N'Client secret'),
    (N'MAILRELAY.COL.SECRETGUELTIGBIS',      N'Secret gültig bis',         N'Secret valid until'),
    (N'MAILRELAY.COL.ERLAUBTEABSENDER',      N'Erlaubte Absender',         N'Allowed senders'),
    (N'MAILRELAY.COL.AKTIV',                 N'Aktiv',                     N'Active'),
    (N'MAILRELAY.COL.LOGIN',                 N'Login',                     N'Login'),
    (N'MAILRELAY.COL.LETZTEANMELDUNG',       N'Letzte Anmeldung',          N'Last login'),
    (N'MAILRELAY.COL.ANGEFORDERT',           N'Angefordert',               N'Requested'),
    (N'MAILRELAY.COL.ANGEFORDERTVON',        N'Angefordert von',           N'Requested by');

DELETE FROM vngSys.Translations WHERE Placeholder IN (SELECT Placeholder FROM @t);
INSERT INTO vngSys.Translations (LanguageCode, Placeholder, Text)
SELECT N'de', Placeholder, De FROM @t
UNION ALL
SELECT N'en', Placeholder, En FROM @t;

COMMIT TRANSACTION;

PRINT N'NextGen-Paket "Mail-Relay" eingespielt. Eintrag im Navigator "' + @ZielNavigator + N'" (nur für Administratoren).';
GO

SET NOEXEC OFF;
GO

