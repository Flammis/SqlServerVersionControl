USE MASTER;
IF ( EXISTS (
  SELECT [Databases].[name] 
  FROM [master].[dbo].[sysdatabases]  AS [Databases]
  WHERE ([Databases].[name] = 'TestVersionCenter')
))
BEGIN
  DROP DATABASE TestVersionCenter;
END
GO

CREATE DATABASE TestVersionCenter;
GO

:SETVAR Path "C:\Users\GustavWi\Documents\GitHub\SqlServerVersionControl\"
:SETVAR ScriptVersionSchema "CreateVersionControlSystem.sql"
USE TestVersionCenter;
:R $(Path)$(ScriptVersionSchema)
GO

USE TestVersionCenter;
DECLARE @Result BIT;
EXEC [versioning].[BeginNewVersion] @NextVersion='1.0.1.0', @Success=@Result OUTPUT, @Comment='TestnewVersion1';
GO

USE TestVersionCenter;
DECLARE @Result BIT;
EXEC [versioning].[AddRevision] @VersionBase='1.0.1.0', @ProgressSqlStatement='CREATE', @RevertSqlStatement='DROP', @Comment='Revision', @Success=@Result OUTPUT;
GO

----Begin new version when previous is incomplete----
USE TestVersionCenter;
BEGIN TRY
  DECLARE @Result BIT;
  EXEC [versioning].[BeginNewVersion] @NextVersion='1.0.2.0', @Success=@Result OUTPUT, @Comment='TestnewVersion2';
END TRY
BEGIN CATCH SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

----Add revision with incorrect base version----
USE TestVersionCenter;
BEGIN TRY
  DECLARE @Result BIT;
  EXEC [versioning].[AddRevision] @VersionBase='1.0.0.0', @ProgressSqlStatement='ALTER', @RevertSqlStatement='ALTER', @Comment='Revision', @Success=@Result OUTPUT;
END TRY
BEGIN CATCH SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

----Add revision with incorrect base version----
USE TestVersionCenter;
BEGIN TRY
  DECLARE @Result BIT;
  EXEC [versioning].[AddRevision] @VersionBase='1.1.0.0', @ProgressSqlStatement='ALTER', @RevertSqlStatement='ALTER', @Comment='Revision', @Success=@Result OUTPUT;
END TRY
BEGIN CATCH SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

----Add revision with correct base version----
USE TestVersionCenter;
DECLARE @Result BIT;
EXEC [versioning].[AddRevision] @VersionBase='1.0.1.0', @ProgressSqlStatement='ALTER', @RevertSqlStatement='ALTER', @Comment='Revision', @Success=@Result OUTPUT;
GO

-------------Test complete version----------------
USE TestVersionCenter;
DECLARE @Result BIT;
EXEC [versioning].[CompleteNewVersion] @Success=@Result OUTPUT, @Comment='NewStableVersion';
SELECT 'All' AS [CMD] ,  [versioning].[SchemaVersion].* FROM [versioning].[SchemaVersion]
UNION
SELECT 'Latest' AS [CMD], [versioning].[LatestVersion].* FROM [versioning].[LatestVersion]
UNION
SELECT 'LatestComplete' AS [CMD], [versioning].[LatestCompleteVersion].* FROM [versioning].[LatestCompleteVersion];
GO

-----------Complete version when it is already completed.---------------
USE TestVersionCenter;
DECLARE @Result BIT;
BEGIN TRY
  EXEC [versioning].[CompleteNewVersion] @Success=@Result OUTPUT, @Comment='NewStableVersion';
END TRY
BEGIN CATCH SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO
-----------------------------------------------------------------
------------------------Create nodes-----------------------------
USE MASTER;
IF ( EXISTS (
  SELECT [Databases].[name] 
  FROM [master].[dbo].[sysdatabases]  AS [Databases]
  WHERE ([Databases].[name] = 'TestVersionNode1')
))
BEGIN
  DROP DATABASE TestVersionNode1;
END
GO

CREATE DATABASE TestVersionNode1;
GO

USE TestVersionCenter;
DECLARE @Result BIT;
BEGIN TRY
  EXEC [versioning].[AddTargetDatabase] @TargetDatabase='TestVersionNode1', @Success=@Result OUTPUT;
END TRY
BEGIN CATCH SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

--DB does not exist--
USE TestVersionCenter;
DECLARE @Result BIT;
BEGIN TRY
  EXEC [versioning].[AddTargetDatabase] @TargetDatabase='TestVersionNode2', @Success=@Result OUTPUT;
END TRY
BEGIN CATCH SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

--DB is VersionCenter INCORRECT--
USE TestVersionCenter;
DECLARE @Result BIT;
BEGIN TRY
  EXEC [versioning].[AddTargetDatabase] @TargetDatabase='TestVersionCenter', @Success=@Result OUTPUT;
END TRY
BEGIN CATCH SELECT ERROR_NUMBER() AS ErrorNumber, ERROR_MESSAGE() AS ErrorMessage;
END CATCH
GO

SELECT * FROM [versioning].[TargetDataBases];

GO