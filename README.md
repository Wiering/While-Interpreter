# WHILE interpreter

This is an old school project from 1998. The objective was to write an interpreter for the language WHILE in Turbo Pascal, and then
write a version of the interpreter in WHILE itself.

## WI / XWI

WI is a WHILE language interpreter for DOS (XWI is the same, but compiled to use extended memory). 
The following functions have been implemented:
```
   read X
   write Y
   hd E
   tl E
   cons E F
   =? E F
   atom=? E F
   while E do C
   case E of F => C
   (* comments *)
```
The input WHILE-program should be an ASCII text file. The default extension is '.WHL'.

The interpreter will call external functions if available on disk:
```
   Y := reverse (X);   (* program 'REVERSE.WHL' is loaded and executed with
                            X as input. The result is stored in Y. *)
```
All variables must start with an uppercase letter.

The scope of the 'while' and 'case' statements are indicated either by ()
or indentation:
```
   while E do      while E do        case E of       case E of
     C1;            (C1; C2)           F => C1;        F => (C1; C2;)
     C2;           D;                       C2;      D;
   D;                                D;
```
The interpreter will allow read X and write X anywhere, not only at the
beginning or end of a program. This can be used to watch variables while
debugging a program.


### Syntax:

wi filename[.whl] [datafile[.dat]] [Options]

 - filename: the name of the file containing the WHILE program to be interpreted.

 - datafile: if supplied, WI will read data from this file, instead of asking the user for input. The file must contain valid WHILE-data. Spaces, tabs and new line characters are ignored.

### Options:

#### -b  Write boolean values
   
   WI will use the expressions true and false when writing output strings.
   
#### -c  Convert program to WHILE-data
   
   WI reads the WHILE program (filename.whl), converts the program to WHILE-data 
   and writes this data to the output file (datafile.dat). WI will ask before overwriting 
   existing files, except with the -o option (overwrite existing files).

#### -f  Formal notation of lists

   When output is displayed, WI will write lists in the following
   form: (a.(b.(c.nil))) instead of (a b c).

#### -h  Highlight variable names in the variable list

   Use this option together with the -t (start in trace mode) or the -v
   (show variables after program has ended) option.

#### -l  Long string output

   When this option is selected, WI will not reduce output values to
   255 characters, but create a Long String (up to 64K) with the
   output, and write this string to stdout, you can use pipes to
   write to a file, for example:
```
      wi int.whl compile.dat -l > output.txt
```
#### -o  Overwrite existing files without asking

   Use this option together with the -c option (convert program to
   WHILE-data).

#### -q  Quiet mode, only display output values or errors messages

   This can be used in batch files to convert files without displaying
   any messages.

#### -t  Start in trace mode

   WI waits for the user to press a key before executing a line of the
   input file. The values of all the variables are shown.

#### -v  List all variables after the WHILE program has ended

   WI will show the variable list after the last write-statement.


### The trace mode:

To enter the trace mode, press Ctrl-C while WI is running your WHILE-
program or enter the -t parameter. WI shows all variables and waits for a
keystroke. Press the Esc key to leave the trace mode and continue
calculating. To halt your program and return to DOS, press Ctrl-C again
from the trace mode.


### Breakpoints:

To set a breakpoint in your program, just add the text 'break' in your
code. WI will start the trace mode at that point while running the
program.


### Watching variables:

By pressing the Tab key while your program is running, you can watch the
variables change. To leave this mode, press Tab again or press Ctrl-C to
start tracing.


## INT.WHL / INT.BAT

INT.WHL is the WHILE interpreter written in WHILE. To run it, use the batch file INT.BAT, which 
will convert the parameters into data files and pass them to the interpreter.

For example, this will run REVERSE.WHL with the parameters (a b):
```
    int reverse - (a b)
    Output: (b a)
```
And this will convert that program into data and run it in the WHILE interpreter INT.WHL:
```
    int int reverse - (a b)
    Output: (b a)
```
You can even let INT.WHL interpret itself (which takes a very long time):
```
    int int int reverse - (a b)
    Output: (b a)
```




