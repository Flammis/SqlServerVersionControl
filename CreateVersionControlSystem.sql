----------Versioning database---------------

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name='versioning')
  EXEC sp_executesql N'CREATE SCHEMA [versioning]'
GO

IF OBJECT_ID('[versioning].[SchemaVersion]') IS NULL
BEGIN
    CREATE TABLE [versioning].[SchemaVersion]
    (
        [SchemaVersionID] INT PRIMARY KEY IDENTITY,
        [ValidFrom] DATETIME NOT NULL,
        [ValidTo] DATETIME NULL,
        [Major] INT NOT NULL,
        [Minor] INT NOT NULL,
        [Build] INT NOT NULL,
        [Revision] INT NOT NULL,
        [ProgressSqlStatement] NVARCHAR(MAX) NOT NULL,
        [RevertSqlStatement] NVARCHAR(MAX) NOT NULL,
        [Comment] NVARCHAR(MAX)
    );
END
GO

IF NOT EXISTS (SELECT TOP 1 * FROM [versioning].[SchemaVersion])
BEGIN
    INSERT INTO [versioning].[SchemaVersion]
        ([ValidFrom], [ValidTo], [Major], [Minor], [Build], [Revision], [ProgressSqlStatement], [RevertSqlStatement])
    VALUES
        (GETUTCDATE(), NULL, 1, 0, 0, 0, '', '')
END
GO

------------------------------------------------------------------------
--------------------Checks if a database exists.------------------------
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND SCHEMA_NAME(schema_id) = 'versioning' AND name = 'ExistsDatabase')
DROP PROCEDURE [versioning].[ExistsDatabase]
GO
CREATE PROCEDURE [versioning].[ExistsDatabase]
(
  @_TargetDatabase NVARCHAR(255),
  @Exists BIT OUTPUT
)
AS
BEGIN
  IF (EXISTS (
    SELECT [Databases].[name] 
    FROM [master].[dbo].[sysdatabases]  AS [Databases]
    WHERE ([Databases].[name] = @_TargetDatabase)
  ))
  BEGIN
    SELECT @Exists = 1;
  END
  ELSE
  BEGIN
    SELECT @Exists = 0;
  END
END
GO

IF OBJECT_ID('[versioning].[TargetDataBases]') IS NULL
  CREATE TABLE [versioning].[TargetDataBases](
    DbName NVARCHAR(255) PRIMARY KEY NOT NULL
  );
GO


------------------------------------------------------------------------
----------------Adds a database to the version control.-----------------

IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND SCHEMA_NAME(schema_id) = 'versioning' AND name = 'AddTargetDatabase')
DROP PROCEDURE [versioning].[AddTargetDatabase]
GO

CREATE PROCEDURE [versioning].[AddTargetDatabase]
(
  @TargetDatabase NVARCHAR(255),
  @Success BIT OUTPUT
)
AS
-- Creates a version schema in the target database.
-- Creates a table in the version schema to track current version of database and to log version history.
-- Adds the database to the list of databases to be tracked. Stored in table [versioning].[TargetDatabases].
-- Parameters:
--    @TargetDatabase - Database to be added to the version system.
BEGIN
  SET @Success = 0;
  IF(LOWER(@TargetDatabase)=LOWER(DB_NAME()))
  BEGIN
    RAISERROR('[AddTargetDatabase]: Cannot use the version control database as target.', 16, 1);
  END

  DECLARE @ExistsDatabase BIT = 0;
  EXEC [versioning].[ExistsDatabase] @_TargetDatabase=@TargetDatabase, @Exists=@ExistsDatabase OUTPUT
  IF (@ExistsDataBase=1)
  BEGIN
    EXEC('
      USE ' + @TargetDatabase +';
      IF NOT EXISTS (
        SELECT SCHEMA_NAME
        FROM [INFORMATION_SCHEMA].[SCHEMATA]
        WHERE SCHEMA_NAME = ''targetversioning''
      )
      BEGIN
        EXEC sp_executesql N''CREATE SCHEMA targetversioning''
      END
    '
    );
    
    DECLARE @TargetSchemaVersion NVARCHAR(255) = '[' + @TargetDatabase + '].[targetversioning].[SchemaVersion]';
    EXEC('
      IF (
        NOT EXISTS (SELECT * 
        FROM [' + @TargetDatabase + '].[INFORMATION_SCHEMA].[TABLES] 
        WHERE TABLE_SCHEMA = ''targetversioning''
        AND  TABLE_NAME = ''SchemaVersion'')
      )
      BEGIN
        CREATE TABLE ' + @TargetSchemaVersion + ' 
        (
            [SchemaVersionID] INT PRIMARY KEY,
            [ValidFrom] DATETIME NOT NULL,
            [ValidTo] DATETIME NULL,
            [Major] INT NOT NULL,
            [Minor] INT NOT NULL,
            [Build] INT NOT NULL,
            [Revision] INT NOT NULL
        )
      END
    ');
    
    INSERT INTO [versioning].[TargetDataBases]
    (
      [DbName]
    ) SELECT @TargetDatabase
    WHERE NOT EXISTS ( SELECT TOP 1 [DbName] FROM [versioning].[TargetDataBases] WHERE [DbName]=@TargetDatabase);

    IF OBJECT_ID(@TargetSchemaVersion) IS NOT NULL
    BEGIN
      EXEC('
          INSERT INTO ' + @TargetSchemaVersion + ' 
          (
            [SchemaVersionID],
            [ValidFrom],
            [Major],
            [Minor],
            [Build],
            [Revision]
          ) SELECT 1, GETUTCDATE(), 1, 0, 0, 0
          WHERE NOT EXISTS(SELECT TOP 1 * FROM ' + @TargetSchemaVersion + ' AS [TargetSchemaVersion])'
      );
    END

    SET @Success = 1;

  END
  ELSE
  BEGIN
    RAISERROR('[AddTargetDatabase]: No database with that name.', 16, 1);
  END
END
GO

------------------------------------------------------------------------
-----------------------Breaks version into four integer.----------------

IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND SCHEMA_NAME(schema_id) = 'versioning' AND name = 'GetVersionParts')
DROP PROCEDURE [versioning].[GetVersionParts]
GO
-- Breaks version into four integers, representing major version number,
-- minor version number, revision number and build number.
-- Parameters:
--    @version - Version specified as dot-separated segments (e.g. 1.2.3.4)
--    @major - On output major version number extracted from @version
--    @minor - On output minor version number extracted from @version
--    @build - On output build number extracted from @version
--    @revision - On output revision number extracted from @version
CREATE PROCEDURE [versioning].[GetVersionParts]
    @version NVARCHAR(255),
    @major INT OUT,
    @minor INT OUT,
    @build INT OUT,
    @revision INT OUT
AS
BEGIN
    DECLARE @startPos INT = 1
    DECLARE @endPos INT

    SET @endPos = CHARINDEX('.', @version, @startPos)
    SET @major = CAST(SUBSTRING(@version, @startPos, @endPos - @startPos) AS INT)
    SET @startPos = @endPos + 1

    SET @endPos = CHARINDEX('.', @version, @startPos)
    SET @minor = CAST(SUBSTRING(@version, @startPos, @endPos - @startPos) AS INT)
    SET @startPos = @endPos + 1

    SET @endPos = CHARINDEX('.', @version, @startPos)
    SET @build = CAST(SUBSTRING(@version, @startPos, @endPos - @startPos) AS INT)
    SET @startPos = @endPos + 1

    SET @endPos = LEN(@version) + 1
    SET @revision = CAST(SUBSTRING(@version, @startPos, @endPos - @startPos) AS INT)

END
GO

IF EXISTS(SELECT * FROM sys.objects WHERE type = 'V' AND SCHEMA_NAME(schema_id) = 'versioning' AND name = 'LatestVersion')
  DROP VIEW [versioning].[LatestVersion];
GO

CREATE VIEW [versioning].[LatestVersion] AS
  SELECT TOP 1 * FROM [versioning].[SchemaVersion]
  ORDER BY [Major] DESC, [Minor] DESC, [Build] DESC, [Revision] DESC
GO

IF EXISTS(SELECT * FROM sys.objects WHERE type = 'V' AND SCHEMA_NAME(schema_id) = 'versioning' AND name = 'LatestCompleteVersion')
  DROP VIEW [versioning].[LatestCompleteVersion];
GO

CREATE VIEW [versioning].[LatestCompleteVersion] AS
  SELECT TOP 1 * FROM [versioning].[SchemaVersion]
  WHERE [Build]%2=0
  ORDER BY [Major] DESC, [Minor] DESC, [Build] DESC, [Revision] DESC
GO

------------------------------------------------------------------------
-------------------------Begin new version.-----------------------------

IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND SCHEMA_NAME(schema_id) = 'versioning' AND name = 'BeginNewVersion')
  DROP PROCEDURE [versioning].[BeginNewVersion]
GO

--Begin new version, requires nextrevision to be odd and newversion > oldversion
--Sets revision number to 0.
CREATE PROCEDURE [versioning].[BeginNewVersion]
(
  @NextVersion NVARCHAR(255),
  @Success BIT OUTPUT,
  @Comment NVARCHAR(255) = NULL
)
AS
BEGIN
  DECLARE @_success BIT = 0;
  SET @Success = 0;
  
  DECLARE @nextmajor INT, @nextminor INT, @nextbuild INT, @nextrevision INT;
  EXEC [versioning].[GetVersionParts] @version=@NextVersion, @major=@nextmajor OUTPUT, @minor=@nextminor OUTPUT, @build=@nextbuild OUTPUT, @revision=@nextrevision OUTPUT;

  DECLARE @CurrentSchemaVersionID INT, @currentmajor INT, @currentminor INT, @currentbuild INT, @currentrevision  INT;
  SELECT
    @CurrentSchemaVersionID=[versioning].[LatestCompleteVersion].[SchemaVersionID],
    @currentmajor=[versioning].[LatestCompleteVersion].[Major],
    @currentminor=[versioning].[LatestCompleteVersion].[Minor],
    @currentbuild=[versioning].[LatestCompleteVersion].[Build],
    @currentrevision=[versioning].[LatestCompleteVersion].[Revision]
  FROM [versioning].[LatestCompleteVersion];
  
    IF @nextmajor < @currentmajor
        SET @_success = 0;
    ELSE IF @nextmajor>@currentmajor
        SET @_success = 1;
    ELSE IF @nextminor < @currentminor
        SET @_success = 0;
    ELSE IF @nextminor > @currentminor
        SET @_success = 1;
    ELSE IF @nextbuild < @currentbuild
        SET @_success = 0;
    ELSE IF @nextbuild > @currentbuild
        SET @_success = 1;
    
    IF(@nextbuild%2=0)
    BEGIN
      RAISERROR('[BeginNewVersion]: Build component of the next version has to be odd.', 16, 1);
    END

    IF(@currentbuild%2=1)
    BEGIN
      RAISERROR('
      Build component of the current version is odd. 
      This mean that the current version is not complete.
      Cannot begin a new version when on an incomplete version.', 16, 1);
    END

    IF (@_success=1)
    BEGIN
   
      INSERT INTO [versioning].[SchemaVersion]
      ([ValidFrom], [ValidTo], [Major], [Minor], [Build], [Revision], [ProgressSqlStatement], [RevertSqlStatement], [Comment])
      VALUES
      (GETUTCDATE(), NULL, @nextmajor, @nextminor, @nextbuild, 0, '', '', @Comment);

      UPDATE [versioning].[SchemaVersion]
      SET [versioning].[SchemaVersion].[ValidTo]=GETUTCDATE()
      WHERE [versioning].[SchemaVersion].[SchemaVersionID]=@CurrentSchemaVersionID;
      
    END  
    ELSE
    BEGIN

      RAISERROR('[BeginNewVersion]: Invalid Parameter @NextVersion', 16, 1);
    
    END

    SET @Success = @_success;

END
GO

------------------------------------------------------------------------
----------------------  -Adds a revision to the build-------------------

IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND SCHEMA_NAME(schema_id) = 'versioning' AND name = 'AddRevision')
  DROP PROCEDURE [versioning].[AddRevision]
GO

CREATE PROCEDURE [versioning].[AddRevision]
(
  @VersionBase NVARCHAR(255),
  @ProgressSqlStatement NVARCHAR(MAX),
  @RevertSqlStatement NVARCHAR(MAX),
  @Comment NVARCHAR(MAX) = NULL,
  @Success BIT OUTPUT
)
AS
-- When creating a new version the build is incremented to an odd number.
-- So if current version is 1.2.2.0 adding a new version increments build number -> 1.2.3.0
-- Then for each Sql statement that con
-- Adds a revision to the new build of the schema.
-- Should only increment the revision for the next version.
-- Parameters:
--    @VersionBase - Base version of the next version. Revision: 1.1.3.10 base -> 1.1.3.0, next version -> 1.1.4.0
--    @ProgressSqlStatement - Statement that defines the modification of the database.
--    @RevertSqlStatement - Statement that reverts back to the previous version of the database.
--    @Comment - Describes the change in the database and it's purpose.
--    @Success - Controll bit to notify if the revision change input was valid.
BEGIN

  IF (@ProgressSqlStatement IS NULL)
  BEGIN
    RAISERROR('[AddRevision]: Invalid Parameter @ProgressSqlStatement', 16, 1);
  END

  IF (@RevertSqlStatement IS NULL)
  BEGIN
    RAISERROR('[AddRevision]: Invalid Parameter @RevertSqlStatement', 16, 1);
  END

  DECLARE @majorInput INT, @minorInput INT, @buildInput INT, @RevisionbaseInput INT;
  EXEC [versioning].[GetVersionParts] @version=@VersionBase, @major=@majorInput OUTPUT, @minor=@minorInput OUTPUT, @build=@buildInput OUTPUT, @revision=@RevisionbaseInput OUTPUT;

  DECLARE @CurrentSchemaVersionID INT, @currentmajor INT, @currentminor INT, @currentbuild INT, @currentrevision  INT;
  SELECT
    @CurrentSchemaVersionID=[versioning].[LatestVersion].[SchemaVersionID],
    @currentmajor=[versioning].[LatestVersion].[Major],
    @currentminor=[versioning].[LatestVersion].[Minor],
    @currentbuild=[versioning].[LatestVersion].[Build],
    @currentrevision=[versioning].[LatestVersion].[Revision]
  FROM [versioning].[LatestVersion];
  
  SET @Success = 0;

  IF @currentmajor=@majorInput AND @currentminor=@minorInput AND @currentbuild=@buildInput AND @RevisionbaseInput=0
  BEGIN
    
    DECLARE @nextRevision INT = @currentrevision + 1;

    INSERT INTO [versioning].[SchemaVersion]
      ([ValidFrom], [ValidTo], [Major], [Minor], [Build], [Revision], [ProgressSqlStatement], [RevertSqlStatement], [Comment])
    VALUES
      (GETUTCDATE(), NULL, @currentmajor, @currentminor, @currentbuild, @nextRevision, @ProgressSqlStatement, @RevertSqlStatement, @Comment);

    UPDATE [versioning].[SchemaVersion]
      SET [versioning].[SchemaVersion].[ValidTo]=GETUTCDATE()
    WHERE [versioning].[SchemaVersion].[SchemaVersionID]=@CurrentSchemaVersionID;

    SET @Success=1;
  END
  ELSE
  BEGIN
    RAISERROR('[AddRevision]: Invalid Parameter @VersionBase', 16, 1);
  END

END
GO

------------------------------------------------------------------------
-------------------------Completes a version.---------------------------

IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND SCHEMA_NAME(schema_id) = 'versioning' AND name = 'CompleteNewVersion')
  DROP PROCEDURE [versioning].[CompleteNewVersion]
GO

CREATE PROCEDURE [versioning].[CompleteNewVersion]
(
  @Success BIT OUTPUT,
  @Comment NVARCHAR(255) = NULL
)
AS
BEGIN
  SET @Success = 0;

  DECLARE @CurrentSchemaVersionID INT, @major INT, @minor INT, @incomplete_build INT, @revision  INT;
  SELECT
    @CurrentSchemaVersionID=[versioning].[LatestVersion].[SchemaVersionID],
    @major=[versioning].[LatestVersion].[Major],
    @minor=[versioning].[LatestVersion].[Minor],
    @incomplete_build=[versioning].[LatestVersion].[Build],
    @revision=[versioning].[LatestVersion].[Revision]
  FROM [versioning].[LatestVersion];

  IF (@incomplete_build%2=1)
  BEGIN
    INSERT INTO [versioning].[SchemaVersion]
      ([ValidFrom], [ValidTo], [Major], [Minor], [Build], [Revision], [ProgressSqlStatement], [RevertSqlStatement], [Comment])
    VALUES
      (GETUTCDATE(), NULL, @major, @minor, @incomplete_build+1, 0, '', '', @Comment);

    UPDATE [versioning].[SchemaVersion]
      SET [versioning].[SchemaVersion].[ValidTo]=GETUTCDATE()
    WHERE [versioning].[SchemaVersion].[SchemaVersionID]=@CurrentSchemaVersionID;

    SET @Success=1;
  END
  ELSE
  BEGIN
    RAISERROR('[CompleteNewVersion]: The latest version is a complete version and cannot therefore not be further completed.', 16, 1);
  END


END
GO

------------------------------------------------------------------------
----------------------Get version of the database.----------------------

IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND SCHEMA_NAME(schema_id) = 'versioning' AND name = 'GetVersionOfDatabase')
  DROP PROCEDURE [versioning].[GetVersionOfDatabase]
GO

CREATE PROCEDURE [versioning].[GetVersionOfDatabase]
(
  @TargetDatabase NVARCHAR(255),
  @DBVersionOUT NVARCHAR(255) OUTPUT,
  @Success BIT OUTPUT
)
AS
BEGIN
  SET @Success = 0;

  IF EXISTS(
    SELECT TOP 1 [DbName] FROM [versioning].[TargetDataBases] WHERE [DbName]=@TargetDatabase
  )
  BEGIN
    DECLARE @TargetSchemaVersion NVARCHAR(255) = '[' + @TargetDatabase + '].[targetversioning].[SchemaVersion]';
    DECLARE @SQLString NVARCHAR(MAX);
    DECLARE @version_internal NVARCHAR(255);
    DECLARE @ParmDefinition NVARCHAR(255);
    SET @SQLString = N'
      SELECT TOP 1 @VersionOUT=CONCAT(CONVERT(NVARCHAR(255), [Major]),CONVERT(NVARCHAR(255), [Minor]), CONVERT(NVARCHAR(255), [Build]), CONVERT(NVARCHAR(255), [Revision]))
      FROM ' + @TargetSchemaVersion + N'
      ORDER BY [Major], [Minor], [Build], [Revision]';
    SET @ParmDefinition = N'@VersionOUT NVARCHAR(255) OUTPUT';

    EXECUTE sp_executesql
    @SQLString,
    @ParmDefinition,
    @VersionOUT= @version_internal OUTPUT;

    SET @DBVersionOUT = @version_internal;
    SET @Success = 1;

  END
  ELSE
  BEGIN
    RAISERROR('[GetVersionOfDatabase]: There is not Target Database with the name.', 16, 1);
  END

END

GO