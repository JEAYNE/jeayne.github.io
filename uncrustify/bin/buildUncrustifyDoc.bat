@echo off
title Runing parseUncrustifyOptions.pl
set BINDIR="%~dp0"
cd /D %BINDIR%
cd

@echo:
perl -V:myuname
IF %ERRORLEVEL% NEQ 0 goto err1
uncrustify --version
IF %ERRORLEVEL% NEQ 0 goto err2
goto run

:err1
echo [91mERROR: Perl is not in installed or not in the PATH"
goto end

:err2
echo [91muncrustify is missing in directory %BINDIR%"
goto end

:run
@echo:
@echo ============================
@echo  Generate default UDS files
@echo ============================
perl .\generateDefaultsUDS.pl

@echo:
@echo =============================================
@echo  Execute each UDS files to generate examples
@echo =============================================
perl .\generateExamples.pl

@echo:
@echo =================================================
@echo  Generate the html documentation for each option
@echo =================================================
perl .\generateUncrustifyOptions.pl

:end
@echo:
echo [93m
pause
echo [0m
