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
perl .\generateExamples.pl --bindir . --inputdir ..\examples --outputdir ..\options

:end
echo [93m
pause
echo [0m
