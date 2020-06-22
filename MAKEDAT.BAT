@echo off
if not x%2x==x-x goto error
if %3x==x goto error
wi %1 %1.$$$ -c -q
echo ( > %1.dat
type %1.$$$ >> %1.dat
echo . >> %1.dat
echo %3 %4 %5 %6 %7 %8 %9 >> %1.dat
echo ) >> %1.dat
echo.
del %1.$$$
goto end
:error
echo usage: makedat file - data
echo.
:end
