@echo off
rem
rem  INT.BAT - WHILE Interpreter Startup
rem  (C) 1998, by Mike Wiering
rem
if %1x==x goto Syntax
set F=%1

if not exist %F%.whl goto Error
if %2x==x goto Run1
if "%2"=="-" goto MakeDat1

if not exist %2.whl goto Error
if %3x==x goto DataReq
if "%3"=="-" goto MakeDat2

if not exist %3.whl goto Error
if %4x==x goto DataReq
if "%4"=="-" goto MakeDat3

if not exist %4.whl goto Error
if %5x==x goto DataReq
if "%5"=="-" goto MakeDat4

echo Too many files
goto End

:MakeDat4
if %6x==x goto DataReq
wi -q %2.whl -c int$dat1.tmp -o
wi -q %3.whl -c int$dat2.tmp -o
wi -q %4.whl -c int$dat3.tmp -o
echo ( > int$dat$.$$$
type int$dat1.tmp >> int$dat$.$$$
echo .( >> int$dat$.$$$
type int$dat2.tmp >> int$dat$.$$$
echo .( >> int$dat$.$$$
type int$dat3.tmp >> int$dat$.$$$
shift
shift
shift
shift
shift
echo . %1 %2 %3 %4 %5 %6 %7 %8 %9 ))) >> int$dat$.$$$
del int$dat1.tmp
del int$dat2.tmp
del int$dat3.tmp
xwi -q %F% int$dat$.$$$ -h
del int$dat$.$$$
goto End

:MakeDat3
if %5x==x goto DataReq
wi -q %2.whl -c int$dat1.tmp -o
wi -q %3.whl -c int$dat2.tmp -o
echo ( > int$dat$.$$$
type int$dat1.tmp >> int$dat$.$$$
echo .( >> int$dat$.$$$
type int$dat2.tmp >> int$dat$.$$$
shift
shift
shift
shift
echo . %1 %2 %3 %4 %5 %6 %7 %8 %9 )) >> int$dat$.$$$
del int$dat1.tmp
del int$dat2.tmp
xwi -q %F% int$dat$.$$$ -h
del int$dat$.$$$
goto End

:MakeDat2
if %4x==x goto DataReq
wi -q %2.whl -c int$dat$.tmp -o
echo ( > int$dat$.$$$
type int$dat$.tmp >> int$dat$.$$$
del int$dat$.tmp
shift
shift
shift
echo . %1 %2 %3 %4 %5 %6 %7 %8 %9 ) >> int$dat$.$$$
xwi -q %F% int$dat$.$$$ -h
del int$dat$.$$$
goto End

:MakeDat1
if %3x==x goto DataReq
shift
shift
echo %1 %2 %3 %4 %5 %6 %7 %8 %9 > int$dat$.$$$
wi -q %F% int$dat$.$$$ -h
del int$dat$.$$$
goto End

:Run1
wi -q %F%
goto End

:Error
echo File not found
goto End

:DataReq
echo Data required
goto End

:Syntax
echo syntax: INT program [program] [- data]

:End
set F=