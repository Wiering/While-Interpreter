program WI;

{
   WHILE Interpreter (C) Copyright 1998, by Mike Wiering

   Programmed in Borland/Turbo Pascal 7.0

   Syntax:

      wi filename[.whl] [datafile[.dat]] [Options]

   Options:

      -b  Boolean values in output
      -c  Convert program to WHILE-data
      -f  Formal notation of lists
      -h  Highlight variable names in the variable list
      -l  Long string output (to stdout)
      -o  Overwrite existing files without asking
      -q  Quiet mode, only display output values or errors messages
      -t  Start in trace mode
      -v  List all variables after the WHILE program has ended
}

{
   History:

     Version 0.10:

        9 Feb 1998 - started project, implemented data structures, parser,
                     expressions, assignment, read, write, hd, tl and cons
       10 Feb 1998 - added while
       12 Feb 1998 - added case, =?, atom=?
       13 Feb 1998 - added error messages etc, mem checking
       14 Feb 1998 - changed parser (indent/()), nested while bug fixed,
                     added tracing option (-t)

     Version 0.20:

       15 Feb 1998 - added multiple files, fixed error position
       16 Feb 1998 - implemented easy notation read/write, added -f option
                     (write lists in formal notation)

     Version 0.30:

       24 Apr 1998 - added data input from file (2nd parameter)
       12 May 1998 - added quote
       13 May 1998 - added parameter -v: show all variables at end
       14 May 1998 - memory of Source[] is disposed

     Version 0.40:

       15 May 1998 - added ^C checking, -h option: highlight variable
                     names
       17 May 1998 - added numbers: (3) -> (nil nil nil)
       24 May 1998 - added -c (Convert WHILE to DATA) and -o (Overwrite)
       25 May 1998 - added break
       26 May 1998 - added -q (quiet mode), watch vars (tab)

     Version 0.50:

        3 Jun 1998 - added more comments
        4 Jun 1998 - fixed LStr Protected Mode memory bug
        5 Jun 1998 - added more comments
        6 Jun 1998 - added long string output (-l), added more comments
        7 Jun 1998 - convert if/then/else, added standard comments etc
        8 Jun 1998 - added -b (Boolean output) flag
}

  {$DEFINE GARBAGE}  { show garbage memory }

  { $DEFINE DEBUG}

  {$M 65000,0,655360}  { large stack }

  {$I-}  { no I/O checking, return errors in IOResult }
  {$X+}  { extended syntax }

  {$IFDEF DEBUG}
    {$R+}  { range checking }
  {$ELSE}
    {$R-}
  {$ENDIF}

  uses
    Dos,
    Crt;


  { global constants and types }

  const
    { total of all source lines (input file + files loaded at runtime) }
    MAX_LINES = $1000;
    MAX_LINE_LENGTH = 128;

  const
    { tab size is important for compound statements (in while/case) }
    DEFAULT_TAB_SIZE = 8;

  const
    { program name, version }
    PROGRAM_NAME = 'wi';
    PROGRAM_VERSION = '0.50';

  const
    { default extensions }
    DEFAULT_EXTENSION = '.whl';
    DEFAULT_DATA_EXTENSION = '.dat';

  const
    { used to allocate memory for variables }
    MAX_VARIABLES = 256;
    MAX_IDENTIFIER_SIZE = 64;

  const
    { external functions run at a higher level, input file is level 0 }
    MAX_LEVELS = 16;

  type
    { record to save cursor position in the source code }
    PosRec =
      record
        Line: LongInt;
        Pos: Integer;
      end;

  type
    { record for a source file at a certain level }
    FileRec =
      record
        Filename: PathStr;
        SourceBase,  { position in Source[] where file starts }
        TotalLines: LongInt;  { number of lines in Source[] }
        VarBase: Integer;  { variables at this level }
        Cursor,  { current position }
        LastPos: PosRec;  { position of last-parsed keyword or char }
      end;

  type
    { pointers to source lines in array Source^[] }
    SourceLinePtr = ^SourceLine;
    SourceLine = string[MAX_LINE_LENGTH];

    SourceLinePtrArrayPtr = ^SourceLinePtrArray;
    SourceLinePtrArray = array[0..MAX_LINES - 1] of SourceLinePtr;

  type
    { used to store values of atoms, max length is 255 }
    StrPtr = ^string;

  type
    { basic structure of WHILE data }
    TreePtr = ^Tree;
    Tree =
      record
      case Atom: Boolean of
        TRUE: (Value: StrPtr);
        FALSE: (Head, Tail: TreePtr);
      end;

  { LongStr type implementation for long strings }

  const
    { maximum line length of LongStr }
    LS_LINE_SIZE = $FF00;

  type
    { the LongStr type }
    LongStrPtr = ^LongStr;
    LongStr = array[0..LS_LINE_SIZE - 1] of Byte;


  { global variables }

  var
    { lspStart contains read statement, lspEnd the write (-c option only) }
    lspStart,
    lspEnd: LongStrPtr;

  var
    { the current level: 0 = input file, 1 is function called, etc. }
    CurLevel: Integer;

  var
    { source lines of WHILE-program (runtime function source is appended) }
    Source: SourceLinePtrArrayPtr;

    { file information for each level }
    Files: array[0..MAX_LEVELS - 1] of FileRec;

    { variable names and values }
    VarNames: array[0..MAX_VARIABLES - 1] of string[MAX_IDENTIFIER_SIZE];
    Values: array[0..MAX_VARIABLES - 1] of TreePtr;

  var
    { command line option flags }
    Tracing,
    Formal,
    FinalShow,
    BoldVars,
    LStrOut,
    Overwrite,
    Convert,
    Quiet,
    Bools: Boolean;

  var
    { watch variables change at run-time when Monitor = TRUE }
    Monitor: Boolean;

  var
    { when tracing, show each line only once }
    LastTraced: LongInt;

  var
    { the current tab-size, always set to DEFAULT_TAB_SIZE }
    TabSize: Integer;

  var
    { name of (input or output) data file }
    WhileData: string;

  {$IFDEF GARBAGE}
  var
    { calculate memory usage }
    LeastMem: LongInt;
  {$ENDIF}


  { general functions }

  function UpCaseStr (s: string): string;
    { returns s in upper-case }
    var
      i: Integer;
  begin  { UpCaseStr }
    for i := 1 to Length (s) do
      s[i] := UpCase (s[i]);
    UpCaseStr := s;
  end;  { UpCaseStr }

  function Exist (f: string): Boolean;
    { returns TRUE if file f exists, else FALSE }
    var
      SR: SearchRec;
  begin  { Exist }
    FindFirst (f, ANYFILE, SR);
    Exist := DOSError = 0;
  end;  { Exist }

  procedure AddExt (var s: string; Ext: string);
    { add an extension to a filename (only if the name has no extension) }
  begin  { AddExt }
    if Pos ('.', s) = 0 then
      if s = UpCaseStr (s) then
        s := s + UpCaseStr (Ext)
      else
        s := s + Ext;
  end;  { AddExt }

  procedure DelSpaces (var s: string);
    { remove leading spaces, tabs and CR/LF from s }
    var
      i, j: Integer;
  begin  { DelSpaces }
    j := SizeOf (s) - 1;
    while (s[1] in [' ', #9, #13, #10]) and (s <> '') do
    begin
      Delete (s, 1, 1);  { delete first character }
      for i := Length (s) + 1 to j do  { clear remainder of string }
        s[i] := #0;
      j := Length (s);  { save last end position }
    end;
  end;  { DelSpaces }

  function GetKey: string;
    { wait for keystroke }
    var
      c: Char;
  begin  { GetKey: }
    c := ReadKey;
    if c = #0 then  { extended character }
      GetKey := c + ReadKey
    else
      GetKey := c;
  end;  { GetKey: }

  procedure ShowInfo;
    { show copyright message }
  begin  { ShowInfo }
    WriteLn ('WHILE Interpreter, version ' + PROGRAM_VERSION +
      ', (C) copyright 1998, by Mike Wiering, Nijmegen.');
  end;  { ShowInfo }

  procedure Abort (Msg: string);
    { show error message and quit }
  begin  { Abort }
    WriteLn (Msg);
    Halt;
  end;  { Abort }

  procedure ShowSyntax;
    { show usage information }
  begin  { ShowSyntax }
    ShowInfo;
    WriteLn;
    WriteLn ('Syntax: ', PROGRAM_NAME, ' filename[' +
        DEFAULT_EXTENSION + '] [datafile[' +
        DEFAULT_DATA_EXTENSION + ']] [Options]');
    WriteLn;
    WriteLn ('Options:');
    WriteLn ('  -b  Boolean values in output.');
    WriteLn ('  -c  Convert program to WHILE-data.');
    WriteLn ('  -f  Use formal list-notation.');
    WriteLn ('  -h  Highlight names when listing variables.');
    WriteLn ('  -l  Long string output to stdout.');
    WriteLn ('  -o  Overwrite existing files without asking.');
    WriteLn ('  -t  Trace source code (press key to continue).');
    WriteLn ('  -v  Show all variables after final output.');
    WriteLn ('  -q  Quiet mode (only display output).');
    Halt;
  end;  { ShowSyntax }

  procedure CheckMem (Size: LongInt);
    { check available memory, abort program if not enough }
    var
      M: LongInt;
  begin  { CheckMem }
    Size := (Size or $000F) + 1;  { memory is used per 16 bytes }
    M := MaxAvail - Size;
  {$IFDEF GARBAGE}
    if M < LeastMem then
      LeastMem := M;
  {$ENDIF}
    if M < $10 then
      Abort ('Out of memory.');
  end;  { CheckMem }


  {
    Long string (LongStr) functions

    A long string is an array of bytes (up to LS_LINE_SIZE bytes), the
    first two bytes contain the length of the string. Every time the string
    is modified, memory is reallocated.
  }

  procedure LStrSetLen (var lsp: LongStrPtr; Length: LongInt);
    { set length, length is stored at the beginning of the string (2 bytes) }
  begin  { LStrSetLen }
    lsp^[0] := Length mod $100;
    lsp^[1] := Length div $100;
  end;  { LStrSetLen }

  function LStrGetLen (var lsp: LongStrPtr): LongInt;
    { get current string length }
  begin  { LStrGetLen }
    LStrGetLen := LongInt (LongInt (lsp^[1] * 256) + lsp^[0]);
  end;  { LStrGetLen }

  procedure LStrInit (var lsp: LongStrPtr);
    { initialize new string }
  begin  { LStrInit }
    CheckMem (2);
    GetMem (lsp, 2);
    LStrSetLen (lsp, 0);
  end;  { LStrInit }

  procedure WriteLongStr (lsp: LongStrPtr);
    { write the contense of LongStr lsp^ to stdout }
    var
      i: Integer;
      T: Text;
  begin  { WriteLongStr }
    Assign (T, '');
    ReWrite (T);
    for i := 0 to LStrGetLen (lsp) - 1 do
      Write (T, Chr (lsp^[i + 2]));
    Close (T);
  end;  { WriteLongStr }

  procedure LStrChangeMem (var lsp: LongStrPtr; NewSize: LongInt);
    { change the size of a string, allocate more memory }
    var
      Len, i: LongInt;
      lsp2: LongStrPtr;
  begin  { LStrChangeMem }
    if NewSize >= LS_LINE_SIZE then
      Abort ('String size exceeds LS_LINE_SIZE');
    Len := LStrGetLen (lsp) + 2;
    { allocate a new string }
    CheckMem (NewSize);
    GetMem (lsp2, NewSize);
    if NewSize < Len then
      Len := NewSize;
    { copy lsp to the new string }
    for i := 0 to Len - 1 do
      lsp2^[i] := lsp^[i];
   { FreeMem (lsp, Len); }  { dangerous! }
    lsp := lsp2;
  end;  { LStrChangeMem }

  procedure LStrAddStr (var lsp: LongStrPtr; s: string);
    { append string s to LongStr lsp^ }
    var
      Len, i: LongInt;
  begin  { LStrAddStr }
    if s = '' then
      Exit;
    Len := LStrGetLen (lsp) + 2;
    LStrChangeMem (lsp, Len + Length (s));
    for i := 0 to Length (s) - 1 do
      lsp^[i + Len] := Ord (s[i + 1]);
    LStrSetLen (lsp, Len - 2 + Length (s));
  end;  { LStrAddStr }

  procedure LStrAddLStr (var lsp: LongStrPtr; lsp2: LongStrPtr);
    { append LongStr lsp2^ to LongStr lsp^ }
    var
      Len, Len2, i: LongInt;
  begin  { LStrAddLStr }
    if lsp2 = nil then
      Exit;
    Len := LStrGetLen (lsp) + 2;
    Len2 := LStrGetLen (lsp2);
    if Len2 = 0 then
      Exit;
    LStrChangeMem (lsp, Len + Len2);
    for i := 0 to Len2 - 1 do
      lsp^[i + Len] := lsp2^[i + 2];
    LStrSetLen (lsp, Len - 2 + Len2);
  end;  { LStrAddLStr }

  procedure LStrInsertStr (var lsp: LongStrPtr; s: string; Pos: LongInt);
    { insert string s into LongStr lsp^ at position Pos }
    var
      Len, i: LongInt;
  begin  { LStrInsertStr }
    if s = '' then
      Exit;
    Len := LStrGetLen (lsp) + 2;
    LStrChangeMem (lsp, Len + Length (s));
    for i := Len - 1 downto Pos do
      lsp^[i + Length (s)] := lsp^[i];
    for i := Length (s) - 1 downto 0 do
      lsp^[2 + Pos - 1 + i] := Ord (s[i + 1]);
    LStrSetLen (lsp, Len - 2 + Length (s));
  end;  { LStrInsertStr }

  procedure LStrInsertLStr (var lsp: LongStrPtr; lsp2: LongStrPtr;
        Pos: LongInt);
    { insert LongStr lsp2^ into LongStr lsp^ at position Pos }
    var
      Len, Len2, i: LongInt;
  begin  { LStrInsertLStr }
    if lsp2 = nil then
      Exit;
    Len := LStrGetLen (lsp) + 2;
    Len2 := LStrGetLen (lsp2);
    if Len2 = 0 then
      Exit;
    LStrChangeMem (lsp, Len + Len2);
    for i := Len - 1 downto Pos do
      lsp^[i + Len2] := lsp^[i];
    for i := Len2 - 1 downto 0 do
      lsp^[2 + Pos - 1 + i] := lsp2^[i + 2];
    LStrSetLen (lsp, Len - 2 + Len2);
  end;  { LStrInsertLStr }

  procedure ReadOption (Option: string);
    { read one command line option and set flags }
    var
      s: string;
  begin  { ReadOption }
    s := UpCaseStr (Option);
    Delete (s, 1, 1);  { delete the '-' or '/' }
    if s = 'T' then
      Tracing := TRUE
    else
      if s = 'F' then
        Formal := TRUE
      else
        if s = 'V' then
          FinalShow := TRUE
        else
          if s = 'H' then
            BoldVars := TRUE
          else
            if s = 'L' then
              LStrOut := TRUE
            else
              if s = 'O' then
                Overwrite := TRUE
              else
                if s = 'C' then
                  Convert := TRUE
                else
                  if s = 'Q' then
                    Quiet := TRUE
                  else
                    if s = 'B' then
                      Bools := TRUE

    else
      WriteLn ('Invalid option: ', Option);
  end;  { ReadOption }

  function ReadCmdLine (var Filename: string; var WhileData: string):
      Boolean;
    { read input, data file and flags from the command line }
    var
      i: Integer;
      s: string;
      Error: Boolean;
  begin  { ReadCmdLine }
    Filename := '';
    WhileData := '';

    { initialize flags }
    Tracing := FALSE;
    Formal := FALSE;
    FinalShow := FALSE;
    BoldVars := FALSE;
    LStrOut := FALSE;
    Overwrite := FALSE;
    Convert := FALSE;
    Quiet := FALSE;
    Bools := FALSE;

    Monitor := FALSE;

    Error := FALSE;
    for i := 1 to ParamCount do
    begin
      s := ParamStr (i);
      if s[1] in ['-', '/'] then
        ReadOption (s)
      else
        if Filename = '' then
          Filename := s
        else
          if WhileData = '' then
            WhileData := s
          else
            Error := TRUE;  { too many parameters }
    end;  { for }
    ReadCmdLine := (Filename <> '') and (not Error);
  end;  { ReadCmdLine }

  function ReadFile (Filename: string; Level: Integer): Boolean;
    { read WHILE-source file into Source[], returns TRUE if all ok }
    var
      F: Text;
      Line: SourceLine;
      i, j,
      Len: Integer;
      s: string;
      VBase: Integer;
      Base: LongInt;
      p: pointer;
  begin  { ReadFile }
    { initialize parameters in Files[] for new level Level }
    Files[Level].Filename := Filename;
    if Level = 0 then  { main input file }
    begin
      Base := 0;  { source line base }
      VBase := 0;  { variable base }
    end
    else
    begin  { function loaded from disk at run-time }
      with Files[Level - 1] do
        Base := SourceBase + TotalLines;
      { set a new base for variables so parent's vars are not harmed }
      i := MAX_VARIABLES;
      while (i > 0) and (VarNames[i - 1] = '') do
        Dec (i);
      VBase := i;
    end;  { else }

    { open the input file }
    ReadFile := FALSE;
    Assign (F, Filename);
    Reset (F);
    if IOResult <> 0 then
      Exit;

    with Files[Level] do
    begin
      Cursor.Line := 0;
      Cursor.Pos := 1;
      LastPos := Cursor;

      SourceBase := Base;
      VarBase := VBase;

      TotalLines := 0;
      repeat
        ReadLn (F, Line);

        { detab string, convert tabs to spaces }
        s := '';
        for i := 1 to Length (Line) do
          if Line[i] = #9 then  { tab character }
          begin
            j := Length (s);
            repeat
              s := s + ' ';
              Inc (j);
            until j mod TabSize = 0;
          end
          else
            s := s + Line[i];

        Line := s;  { ** no line length checking ** }

        if Line = '' then  { lines must have at least one character }
          Line := ' ';
        Len := Length (Line);
        CheckMem (Len + 1);
        GetMem (Source^[SourceBase + TotalLines], Len + 1);

        { store new line in Source[] }
        Source^[SourceBase + TotalLines]^ := Line;
        Inc (TotalLines);
      until Eof (F) or (IOResult <> 0) or
          (SourceBase + TotalLines > MAX_LINES - 1);
    end;  { with }
    Close (F);

    ReadFile := TRUE;
  end;  { ReadFile }

  function GetSourceLine (Line: LongInt): string;
    { returns a source line from the WHILE program stored in Source[] }
  begin  { GetSourceLine }
    with Files[CurLevel] do
      if Line >= TotalLines then
        GetSourceLine := ''
      else
        GetSourceLine := Source^[SourceBase + Line]^;
  end;  { GetSourceLine }

  procedure Error (Msg: string; Position: PosRec);
    { show exact error position in source }
  begin  { Error }
    with Position do
    begin
      WriteLn ('Error in line ', Line + 1, ': ', Msg);
      WriteLn (GetSourceLine (Line));
      WriteLn ('^': Pos);
    end;
    Halt;
  end;  { Error }

  procedure SavePos (var Buf: PosRec; var Last: PosRec);
    { save the current Cursor/LastPos position in Buf and Last }
  begin  { SavePos }
    with Files[CurLevel] do
    begin
      Buf := Cursor;
      Last := LastPos;
    end;
  end;  { SavePos }

  procedure RestorePos (Buf, Last: PosRec);
    { restore a saved position }
  begin  { RestorePos }
    with Files[CurLevel] do
    begin
      LastPos := Last;
      Cursor := Buf;
    end;
  end;  { RestorePos }


  { parse functions }

  function GetC: Char;
    { get next char from file and move Cursor }
    var
      C: Char;
  begin  { GetC: }
    with Files[CurLevel] do
      with Cursor do
      begin
        if (Line >= TotalLines) then
          C := #0  { indicate end of file }
        else
          if Pos > Length (Source^[SourceBase + Line]^) then
          begin
            C := #13;  { new line }
            Inc (Line);
            Pos := 1;
          end
          else
          begin
            { return next character }
            C := Source^[SourceBase + Line]^[Pos];
            if C in [#0] then
              C := ' ';  { in case the file contains a #0 char }
            Inc (Pos);
          end;  { else }
      end;  { with }
    GetC := C;
  end;  { GetC: }

  function LookAheadChar: Char;
    { get next char without moving cursor }
    var
      Buf, Last: PosRec;
  begin  { LookAheadChar: }
    SavePos (Buf, Last);
    LookAheadChar := GetC;
    RestorePos (Buf, Last);
  end;  { LookAheadChar: }

  procedure CheckEnd (c: Char);
    { halt program if end-of-file found }
  begin  { CheckEnd }
    if c = #0 then
      Error ('Unexpected end of file.', Files[CurLevel].Cursor);
  end;  { CheckEnd }

  function GetToken (MoveCursor: Boolean): string;
    { get next symbol or word, skip comments }
    var
      s: string;
      c: Char;
      Buf, Last: PosRec;
      Comment: Boolean;
  begin  { GetToken }
    if not MoveCursor then
      SavePos (Buf, Last);
    s := '';
    repeat
      Comment := FALSE;
      c := GetC;
      if (c = '(') and (LookAheadChar = '*') then  { comment start }
      begin
        Comment := TRUE;
        c := GetC;  { skip '*' }
        repeat
          c := GetC;
          CheckEnd (c);  { halts if end of file }
        until (c = '*') and (LookAheadChar = ')');  { comment end }
        c := GetC;  { skip ')' }
      end;
    until (not (c in [#13, #10, ' '])) and (not Comment);

    with Files[CurLevel] do  { save start position of token in LastPos }
    begin
      LastPos := Cursor;
      Dec (LastPos.Pos);
    end;

    if c in ['0'..'9'] then  { number }
    begin
      while LookAheadChar in ['0'..'9'] do
      begin
        s := s + c;
        c := GetC;
      end;
      s := s + c;
    end
    else
      if UpCase (c) in ['A'..'Z', '_'] then  { (key)word/identifier }
      begin
        while (UpCase (LookAheadChar) in ['A'..'Z', '_', '0'..'9']) do
        begin
          s := s + c;
          c := GetC;
        end;
        s := s + c;
      end
      else
        s := c;  { symbol }

    if not MoveCursor then
      RestorePos (Buf, Last);
    GetToken := s;
  end;  { GetToken }

  function CheckToken (Token: string): Boolean;
    { checks for Token and returns TRUE if found (and moves cursor) }
    var
      Buf, Last: PosRec;
      s: string;
  begin  { CheckToken }
    SavePos (Buf, Last);
    s := '';
    { Token may be a combination of characters }
    repeat
      s := s + GetToken (TRUE);
    until Length (s) >= Length (Token);
    if s = Token then
      CheckToken := TRUE
    else
    begin
      RestorePos (Buf, Last);  { resture old position }
      CheckToken := FALSE;
    end;  { else }
  end;  { CheckToken }

  procedure Expect (Token: string);
    { halts if Token is not found at the current position }
    var
      s: string;
  begin  { Expect }
    with Files[CurLevel] do
      if not CheckToken (Token) then
      begin
        s := GetToken (TRUE);
        Error (#39 + Token + #39' expected.', LastPos);
      end;
  end;  { Expect }


  { tree functions }

  procedure ClearNode (Tree: TreePtr);
    { clear a node, Tree must be initialized }
  begin  { ClearNode }
    with Tree^ do
    begin
      Atom := FALSE;
      Value := nil;
      Head := nil;
      Tail := nil;
    end;
  end;  { ClearNode }

  function Cons (Hd, Tl: TreePtr): TreePtr;
    { returns cons Hd Tl }
    var
      Root: TreePtr;
  begin  { Cons }
    { only one new node is created with pointers to Hd and Tl }
    CheckMem (SizeOf (Tree));
    GetMem (Root, SizeOf (Tree));
    ClearNode (Root);
    Root^.Head := Hd;
    Root^.Tail := Tl;
    Cons := Root;
  end;  { Cons }

  function ReadFileData (var s: string; var F: Text): TreePtr;
    { recursive function to read WHILE data from text file F }
    var
      Root, Cur: TreePtr;
      Atom: string;
      L: Integer;
      c: Char;

    procedure RunNumbers (var s: string);
      { convert numbers to sequences of NILs (used for variable numbers),
        3 => NIL NIL NIL }
      var
        t: string;
        i: Integer;
        L: LongInt;
    begin  { RunNumbers }
      { because large numbers are allowed, only add one NIL at a time }
      t := '';
      while (s <> '') and (s[1] in ['0'..'9']) do  { get number in t }
      begin
        t := t + s[1];
        Delete (s, 1, 1);
      end;
      if t <> '' then  { number found }
      begin
        Val (t, L, i);
        if i <> 0 then  { not a valid number, don't convert }
          s := t + s
        else
        begin
          { valid number, string s becomes NIL+(L-1)+... }
          Dec (L);
          if L > 0 then  { not the last NIL? }
          begin
            Str (L, t);
            s := t + s;
          end;
          s := 'nil ' + s;
        end;  { else }
      end;  { if }
    end;  { RunNumbers }

  begin  { ReadFileData }
    { string s is used as FIFO buffer between file F and tree }
    if not Eof (F) then
      { append more data from file F to s }
      while (Length (s) < SizeOf (s) div 2) and (not Eof (F)) do
      begin
        Read (F, c);
        if not (c in [#10, #13]) then  { remove CR/LF }
          s := s + c;
      end;

    { check for numbers, replace with NILs }
    RunNumbers (s);

    { s starts with 'nil', return NIL }
    if (Copy (s, 1, 3) = 'nil') and
      ((Length (s) = 3) or (not (UpCase (s[4]) in ['A'..'Z']))) then
    begin
      ReadFileData := nil;
      Delete (s, 1, 3);
      Exit;
    end;

    { initialize new tree in Root }
    CheckMem (SizeOf (Tree));
    GetMem (Root, SizeOf (Tree));
    ClearNode (Root);
    if s[1] = '(' then
    begin
      Root^.Atom := FALSE;
      Delete (s, 1, 1);  { '(' }
      DelSpaces (s);
      { '()' is the same as NIL, can be used for numbers ()()() = 3 }
      if s[1] = ')' then
      begin
        FreeMem (Root, SizeOf (Tree));
        Root := nil;
        Delete (s, 1, 1);
      end
      else
      begin
        Root^.Head := ReadFileData (s, F);  { read Head }
        DelSpaces (s);
        if s[1] = '.' then  { expression (X.Y) }
        begin
          Delete (s, 1, 1);  { '.' }
          DelSpaces (s);
          Root^.Tail := ReadFileData (s, F);  { read Tail }
          DelSpaces (s);
          if s[1] <> ')' then
            Abort ('Syntax error, '')'' expected.');
          Delete (s, 1, 1);  { ')' }
        end
        else  { expression (X Y Z ...) }
        begin
          DelSpaces (s);
          Cur := Root;
          while (s <> '') and (s[1] <> ')') do  { read a list }
          begin
            Cur^.Tail := Cons (ReadFileData (s, F), nil);
            Cur := Cur^.Tail;
            DelSpaces (s);
          end;
          if (s = '') or (s[1] <> ')') then
            Abort ('Syntax error, '')'' expected.');
          Delete (s, 1, 1);  { ')' }
        end;  { else }
      end;  { else }
    end  { if }
    else  { expression is an atom }
    begin
      DelSpaces (s);
      { read the atom }
      Atom := '';
      while (s <> '') and (not (s[1] in [' ', '.', ')'])) do
      begin
        Atom := Atom + s[1];
        Delete (s, 1, 1);
      end;
      { store the atom in Root }
      L := Length (Atom) + 1;
      CheckMem (L);
      GetMem (Root^.Value, L);
      Root^.Value^ := Atom;
      Root^.Atom := TRUE;
    end;  { else }
    ReadFileData := Root;
  end;  { ReadFileData }

  function ReadTree (var s: string): TreePtr;
    { read a tree from string s, used for input from keyboard }
    var
      Root, Cur: TreePtr;
      Atom: string;
      L: Integer;
  begin  { ReadTree }
    { s starts with 'nil', return NIL }
    if (Copy (s, 1, 3) = 'nil') and
      ((Length (s) = 3) or (not (UpCase (s[4]) in ['A'..'Z']))) then
    begin
      ReadTree := nil;
      Delete (s, 1, 3);
      Exit;
    end;

    { initialize new tree in Root }
    CheckMem (SizeOf (Tree));
    GetMem (Root, SizeOf (Tree));
    ClearNode (Root);
    if s[1] = '(' then
    begin
      Root^.Atom := FALSE;
      Delete (s, 1, 1);  { '(' }
      DelSpaces (s);
      { '()' is the same as NIL, can be used for numbers ()()() = 3 }
      if s[1] = ')' then
      begin
        Root := nil;
        Delete (s, 1, 1);
      end
      else
      begin
        Root^.Head := ReadTree (s);  { read Head }
        if s[1] = '.' then  { expression (X.Y) }
        begin
          Delete (s, 1, 1);  { '.' }
          DelSpaces (s);
          Root^.Tail := ReadTree (s);  { read Tail }
          DelSpaces (s);
          if s[1] <> ')' then
            Abort ('Syntax error, '')'' expected.');
          Delete (s, 1, 1);  { ')' }
        end
        else  { expression (X Y Z ...) }
        begin
          DelSpaces (s);
          Cur := Root;
          while (s <> '') and (s[1] <> ')') do  { build a list }
          begin
            Cur^.Tail := Cons (ReadTree (s), nil);
            Cur := Cur^.Tail;
            DelSpaces (s);
          end;
          if (s = '') or (s[1] <> ')') then
            Abort ('Syntax error, '')'' expected.');
          Delete (s, 1, 1);  { ')' }
        end;  { else }
      end;  { else }
    end  { if }
    else  { expression is an atom }
    begin
      DelSpaces (s);
      { read the atom }
      Atom := '';
      while (s <> '') and (not (s[1] in [' ', '.', ')'])) do
      begin
        Atom := Atom + s[1];
        Delete (s, 1, 1);
      end;
      { store the atom in Root }
      L := Length (Atom) + 1;
      CheckMem (L);
      GetMem (Root^.Value, L);
      Root^.Value^ := Atom;
      Root^.Atom := TRUE;
    end;  { else }
    ReadTree := Root;
  end;  { ReadTree }

  function FormalToEasy (s: string): string;
    { converts s to easy notation (a.(b.nil)) => (a b) }
    var
      i, j, k,
      Level: Integer;
  begin  { FormalToEasy }
    { replace '(' X '.nil)' with '(' X ')' }
    if (s[1] = '(') and (Copy (s, Length (s) - 4, 5) = '.nil)') then
      Delete (s, Length (s) - 4, 4);

    { continue until length of s doesn't change }
    j := 0;
    while j <> Length (s) do
    begin
      j := Length (s);  { save current length }

      { replace X '.(' Y ')' with X ' ' Y }
      i := Pos ('.(', s);
      k := i + 2;
      Level := 0;
      { find matching ')', skip '((...))' }
      while (k < Length (s)) and
          ((not (s[k] in ['.', ')'])) or (Level <> 0)) do
      begin
        if s[k] = '(' then
          Inc (Level);
        if s[k] = ')' then
          Dec (Level);
        Inc (k);
      end;
      if (k < Length (s)) and (s[k] = ')') then
      begin
        { delete ')' }
        Delete (s, k, 1);
        { replace '.(' with ' ' }
        Delete (s, i, 1);
        s[i] := ' ';
      end;
    end;  { while }
    FormalToEasy := s;
  end;  { FormalToEasy }

  function WriteLTree (Tree: TreePtr; Level: Integer): LongStrPtr;
    { convert a tree to a LongStr }
    const
      MAX_LEVEL = 100;
    var
      lsp: LongStrPtr;
  begin  { WriteLTree }
    if Level > MAX_LEVEL then
    begin
      { recursion level too deep, avoid stack overflow }
      WriteLTree := nil;
      Exit;
    end;
    if Tree = nil then
    begin
      LStrInit (lsp);
      if Bools then
        LStrAddStr (lsp, 'false')
      else
        LStrAddStr (lsp, 'nil');
      WriteLTree := lsp;
    end
    else
      case Tree^.Atom of
        TRUE:
          begin
            LStrInit (lsp);
            LStrAddStr (lsp, Tree^.Value^);
            WriteLTree := lsp;
          end;  { if }
        FALSE:
          begin
            LStrInit (lsp);
            if Bools and (Tree^.Head = nil) and (Tree^.Tail = nil) then
              LStrAddStr (lsp, 'true')
            else
            begin
              LStrAddStr (lsp, '(');
              LStrAddLStr (lsp, WriteLTree (Tree^.Head, Level + 1));
              LStrAddStr (lsp, '.');
              LStrAddLStr (lsp, WriteLTree (Tree^.Tail, Level + 1));
              LStrAddStr (lsp, ')');
            end;  { else }

  {          if not Formal then
              s := FormalToEasy (s);  { convert (sub)tree to easy notation }
            WriteLTree := lsp;
          end;
      end;  { case }
  end;  { WriteLTree }

  function WriteTree (Tree: TreePtr; Level: Integer): string;
    { convert a tree to a string, max length: 255 }
    const
      MAX_LEVEL = 30;  { recursion level }
    var
      s: string;
  begin  { WriteTree }
    if Level > MAX_LEVEL then
    begin
      { (sub)tree doesn't fit in the string }
      WriteTree := '';
      Exit;
    end;
    if Tree = nil then
    begin
      if Bools then
        WriteTree := 'false'
      else
        WriteTree := 'nil';
    end
    else
      case Tree^.Atom of
        TRUE:
          WriteTree := Tree^.Value^;
        FALSE:
          begin
            s := '(' + WriteTree (Tree^.Head, Level + 1) + '.' +
                WriteTree (Tree^.Tail, Level + 1) + ')';
            if Bools then
              if s = '(false.false)' then
                s := 'true';
            if not Formal then
              s := FormalToEasy (s);  { convert (sub)tree to easy notation }
            WriteTree := s;
          end;
      end;  { case }
  end;  { WriteTree }

  {
    FreeTree is dangerous to use, because other trees may still be linked
    to parts of Root, or the tree in Root may have pointers to other trees
    that should not be destroyed. FreeTree will also not work if the tree
    contains a pointer to itself.
  }

  procedure FreeTree (var Root: TreePtr);
    { free all memory used by a tree }
  begin  { FreeTree }
    if Root <> nil then
    begin
      case Root^.Atom of
        TRUE:
          begin
            FreeMem (Root^.Value, Length (Root^.Value^) + 1);
            Root^.Value := nil;
          end;
        FALSE:
          begin
            FreeTree (Root^.Head);
            FreeTree (Root^.Tail);
          end;
      end;
      if Root <> nil then
      begin
        FreeMem (Root, SizeOf (Tree));
        Root := nil;
      end;
    end;  { if }
  end;  { FreeTree }


  procedure InitVars;
    { initialize buffers for variables }
    var
      i: Integer;
  begin  { InitVars }
    for i := 0 to MAX_VARIABLES - 1 do
    begin
      VarNames[i] := '';
      Values[i] := nil;
    end;
  end;  { InitVars }

  procedure StoreVar (VarName: string; Value: TreePtr);
    { assigns Value to VarName, creates new variable if it doesn't exist }
    var
      i: Integer;
  begin  { StoreVar }
    { ignore parent's variables }
    for i := Files[CurLevel].VarBase to MAX_VARIABLES - 1 do
      if VarNames[i] = VarName then
      begin
       { if Values[i] <> nil then
          FreeTree (Values[i]); }  { old value must remain allocated! }
        Values[i] := Value;
        Exit;
      end;
    { new variable, find place to store }
    i := Files[CurLevel].VarBase;
    while (i < MAX_VARIABLES) and (VarNames[i] <> '') do
      Inc (i);
    if not (i < MAX_VARIABLES) then
      Error ('Too many variables.', Files[CurLevel].LastPos);
    { store the new variable }
    VarNames[i] := Copy (VarName, 1, MAX_IDENTIFIER_SIZE);
    Values[i] := Value;
  end;  { StoreVar }

  function GetVar (VarName: string): TreePtr;
    { return value of a variable }
    var
      i: Integer;
  begin  { GetVar }
    { search for variable }
    for i := Files[CurLevel].VarBase to MAX_VARIABLES - 1 do
      if VarNames[i] = VarName then
      begin
        GetVar := Values[i];
        Exit;
      end;
    { variable not found, return NIL }
    GetVar := nil;
  end;  { GetVar }

  {
    When converting a WHILE program into WHILE-data, all variables must be
    replaced with (var N) where N is the number of the variable.
  }

  function GetVarNumber (VarName: string): Integer;
    { returns the number of a variable, 0 if not yet defined }
    var
      i: Integer;
  begin  { GetVarNumber }
    for i := Files[CurLevel].VarBase to MAX_VARIABLES - 1 do
      if VarNames[i] = VarName then
      begin
        GetVarNumber := Succ (i);
        Exit;
      end;
    GetVarNumber := 0;
  end;  { GetVarNumber }

  function ConvVar (VarName: string): string;
    { store a new variable (only to remember it's number) }
    var
      s: string;
      i: Integer;
  begin  { ConvVar }
    { if no var name given, get it from the source }
    if VarName = '' then
      VarName := GetToken (TRUE);
    if not (VarName[1] in ['A'..'Z']) then
      Error ('Identifier expected.', Files[CurLevel].LastPos);
    i := GetVarNumber (VarName);
    if i = 0 then
    begin
      { just assign nil to the variable }
      StoreVar (VarName, nil);
      i := GetVarNumber (VarName);
    end;
    Str (i, s);
    ConvVar := s;
  end;  { ConvVar }


  { debugging/tracing functions }

  procedure ListVars;
    { show a list of all variables (for debugging) }
    var
      i, j, Level: Integer;
      First: Boolean;
      s: string;
  begin  { ListVars }
    Level := CurLevel;  { save CurLevel }
    for j := 0 to CurLevel do
    begin
      CurLevel := j;  { show variables of all levels seperately }
      First := TRUE;
      for i := Files[j].VarBase to MAX_VARIABLES - 1 do
        if (VarNames[i] <> '') and
            ((j = Level) or (i < Files[j + 1].VarBase)) then
        begin
          if First then
          begin
            if not (Monitor and (CurLevel = 0)) then
              WriteLn;
          end
          else
            Write (', ');
          First := FALSE;
          if BoldVars then  { -h option }
            HighVideo;
          { write variable name }
          Write (VarNames[i]);
          if BoldVars then
            LowVideo;
          { write value }

          s := WriteTree (GetVar (VarNames[i]), 1);
          Write ('=', s);
          if s[0] = #255 then
            Write ('...');
        end;  { if }
    end;  { for }
    if Monitor then  { watching variables at run-time? }
      ClrEol;
    WriteLn;
    CurLevel := Level;  { restore CurLevel }
  end;  { ListVars }

  procedure Trace;
    { trace code line by line, display variables and wait for keystroke }
    var
      Line: LongInt;
      s: string[2];
  begin  { Trace }
    with Files[CurLevel] do
    begin
      Line := LastPos.Line;
      { only trace a line once, skip empty lines }
      if (LastTraced <> Line + SourceBase) and
          (GetSourceLine (Line) <> '') then
      begin
        { display all variables and current source line }
        ListVars;
        WriteLn;
        Write (Filename, '(', Line + 1, '): ', GetSourceLine (Line));
        LastTraced := Line + SourceBase;
        s := GetKey;
        WriteLn;
        if s = #3 then  { ^C pressed, halt program }
          Abort ('^C program halted.');
        if s = #27 then  { Esc pressed, leave trace mode }
          Tracing := FALSE;
        if s = #9 then  { Tab pressed, watch variables }
        begin
          ClrScr;
          Monitor := TRUE;
        end;
      end;  { if }
    end;  { with }
  end;  { Trace }

  function CompareExpr (Expr1, Expr2: TreePtr; Atomic: Boolean): Boolean;
    { compare two trees, WHILE: =? or atom=? }
    var
      N1, N2: Boolean;
  begin  { CompareExpr }
    N1 := Expr1 = nil;
    N2 := Expr2 = nil;
    if (N1 and N2) then
      CompareExpr := TRUE  { ** and not Atomic **  atom=? nil nil  }
    else
      if (N1 xor N2) then
        CompareExpr := FALSE  { one of the expressions is NIL }
      else
        if (Expr1^.Atom xor Expr2^.Atom) then
          CompareExpr := FALSE  { only one of the expressions is an atom }
        else
          if not (Expr1^.Atom or Expr2^.Atom) then
          begin
            { ** if Atomic then CompareExpr := FALSE else ** }
            { compare branches }
            CompareExpr := CompareExpr (Expr1^.Head, Expr2^.Head, Atomic)
              and CompareExpr (Expr1^.Tail, Expr2^.Tail, Atomic);
          end
          else
            { compare leaves of tree, both atoms }
            CompareExpr := (Expr1^.Value^ = Expr2^.Value^);
  end;  { CompareExpr }


  {
    Statement () runs one statement, this may contain other compound
    statements (while/case).
    The return variable LongStrPtr is only used when converting a program
    to WHILE-data, returns Statment's converted code.
  }

  function Statement (s: string; lspPrev: LongStrPtr): LongStrPtr; forward;
    { function prototype for Statement }

  {
    When a function is loaded from disk during run-time, the result value
    is passed back to the parent in a temporary variable named _tmp_X,
    where X is the current level.
  }

  function ResultVarName (Level: Integer): string;
    { name for var to pass result of higher level }
  begin  { ResultVarName }
    ResultVarName := '_tmp_' + Chr (Ord ('1') + CurLevel);
  end;  { ResultVarName }

  function RunFile (Name: string): TreePtr;
    { load an external function from disk, run it at a higher level
      and then return the result to the current level }
    var
      s: string;
      i: Integer;
  begin  { RunFile }
    { add extension to find the function on disk }
    AddExt (Name, DEFAULT_EXTENSION);

    { only allow MAX_LEVELS nested functions }
    if CurLevel + 1 >= MAX_LEVELS then
      Error ('Function nested too deep.', Files[CurLevel].LastPos);

    { create a temporary return variable for result value }
    StoreVar (ResultVarName (CurLevel), nil);

    ReadFile (Name, CurLevel + 1);

    Inc (CurLevel);  { run the child function at a higher level }

    { run the function }
    s := GetToken (TRUE);
    while s <> #0 do
    begin
      Statement (s, nil);
      s := GetToken (TRUE);
    end;

    { clear local vars }
    for i := Files[CurLevel].VarBase to MAX_VARIABLES - 1 do
      if VarNames[i] <> '' then
        VarNames[i] := '';

    Dec (CurLevel);  { we're back at the parent, continue parsing }
    Expect (')');  { closing ')' for function parameter }

    { return result value }
    s := ResultVarName (CurLevel);
    RunFile := GetVar (s);

    { remove tmp var _tmp_X }
    for i := Files[CurLevel].VarBase to MAX_VARIABLES - 1 do
      if VarNames[i] = s then
        VarNames[i] := '';
  end;  { RunFile }

  function ConvExpr: LongStrPtr;
    { convert an expression to WHILE-data (-c option only) }
    var
      lsp: LongStrPtr;
      s: string;
      i: Integer;
  begin  { ConvExpr }
    s := '';
    if CheckToken ('nil') or CheckToken ('false') then
      s := '(quote nil)'
    else
      if CheckToken ('hd') then
        s := '(hd '#0')'  { #0 is code to call ConvExpr() again }
      else
        if CheckToken ('tl') then
          s := '(tl '#0')'
        else
          if CheckToken ('cons') then
            s := '(cons '#0' '#0')'
          else
            if CheckToken ('atom') and CheckToken ('=?') then
              s := '(atom=? '#0' '#0')'
            else
              if CheckToken ('=?') then
                s := '(=? '#0' '#0')'
              else
                if CheckToken ('quote') then
                begin
                  s := GetToken (TRUE);
                  if s = 'atom' then
                    s := s + GetToken (TRUE);
                  { get ':=' and '=?', 'atom=?' as one token }
                  if (s = ':') or (s[Length (s)] = '=') then
                    s := s + GetToken (TRUE);
                  s := '(quote ' + s + ')'
                end
                else
                  if CheckToken ('(') then
                    s := #0
                  else
                  begin
                    s := GetToken (TRUE);
                    if s[1] in ['A'..'Z'] then
                      s := '(var ' + ConvVar (s) + ')'
                    else
                      s := '(quote ' + s + ')';
                  end;  { else }

    if s = '' then
      ConvExpr := nil
    else
    begin
      LStrInit (lsp);

      { replace #0 in s with the result of ConvExpr (recursive) }
      if s = #0 then
      begin
        s := '';
        LStrAddLStr (lsp, ConvExpr);
        if CheckToken ('.') then
        begin
          LStrInsertStr (lsp, '(', 1);
          LStrAddStr (lsp, '.');
          LStrAddLStr (lsp, ConvExpr);
          s := ')';
        end;
        Expect (')');
      end;  { if }

      i := Pos (#0, s);
      if i > 0 then
      begin
        LStrAddStr (lsp, Copy (s, 1, i - 1));
        LStrAddLStr (lsp, ConvExpr);
        Delete (s, 1, i);
        i := Pos (#0, s);
        if i > 0 then
        begin
          LStrAddStr (lsp, Copy (s, 1, i - 1));
          LStrAddLStr (lsp, ConvExpr);
          Delete (s, 1, i);
        end;
      end;  { if }
      LStrAddStr (lsp, s);

      ConvExpr := lsp;
    end;  { else }
  end;  { ConvExpr }


  function ReadExpr: TreePtr;
    { parse an expression and return a WHILE-tree (recursive) }
    var
      s, t: string;
      TmpTree,
      Tree1,
      Tree2: TreePtr;
      P, L: PosRec;
  begin  { ReadExpr }
    if CheckToken ('nil') then
    begin
      ReadExpr := nil;
      Exit;
    end;

    if CheckToken ('(') then
    begin
      TmpTree := ReadExpr;
      if not CheckToken ('.') then  { expression '(' E ')' }
        ReadExpr := TmpTree
      else
      begin  { expression '(' E1 '.' E2 ')' }
        Tree1 := TmpTree;
        Tree2 := ReadExpr;
        { create a new node }
        CheckMem (SizeOf (Tree));
        GetMem (TmpTree, SizeOf (Tree));
        ClearNode (TmpTree);
        TmpTree^.Head := Tree1;
        TmpTree^.Tail := Tree2;
        ReadExpr := TmpTree;
      end;  { else }
      Expect (')');
      Exit;
    end;  { if }

    { expression '=?' E1 E2 }
    if CheckToken ('=?') then
    begin
      if CompareExpr (ReadExpr, ReadExpr, FALSE) then
        s := 'true'
      else
        s := 'false';
    end
    else
      { expression 'atom=?' E1 E2 }
      if CheckToken ('atom') and CheckToken ('=?') then
      begin
        if CompareExpr (ReadExpr, ReadExpr, TRUE) then
          s := 'true'
        else
          s := 'false';
      end
      else
        s := GetToken (TRUE);

    { expression 'hd' E }
    if s = 'hd' then
    begin
      TmpTree := ReadExpr;
      if TmpTree = nil then
        ReadExpr := nil
      else
        if TmpTree^.Atom then
          ReadExpr := nil      { ** hd Atom = nil ** }
        else
          ReadExpr := TmpTree^.Head;
    end
    else
      { expression 'tl' E }
      if s = 'tl' then
      begin
        TmpTree := ReadExpr;
        if TmpTree = nil then
          ReadExpr := nil
        else
          if TmpTree^.Atom then
            ReadExpr := nil      { tl Atom = nil }
          else
            ReadExpr := TmpTree^.Tail;
      end
      else
        { expression 'cons' E1 E2 }
        if s = 'cons' then
        begin
          Tree1 := ReadExpr;
          Tree2 := ReadExpr;
          CheckMem (SizeOf (Tree));
          GetMem (TmpTree, SizeOf (Tree));
          ClearNode (TmpTree);
          TmpTree^.Head := Tree1;
          TmpTree^.Tail := Tree2;
          ReadExpr := TmpTree;
        end
        else
          { expression 'nil' or 'false' }
          if (s = 'nil') or (s = 'false') then
            ReadExpr := nil
          else
            { variable }
            if s[1] in ['A'..'Z'] then
              ReadExpr := GetVar (s)
            else
              { expression 'true' }
              if s = 'true' then
              begin
                CheckMem (SizeOf (Tree));
                GetMem (TmpTree, SizeOf (Tree));
                ClearNode (TmpTree);
                ReadExpr := TmpTree;
              end
              else
              begin
                { external function?: load from disk }
                SavePos (P, L);
                t := s;  { filename }
                if CheckToken ('.') then
                  t := t + '.' + GetToken (TRUE);  { add extension }
                { expression filename '(' E ')'
                      or     filename.ext '(' E ')' }
                if CheckToken ('(') then
                  ReadExpr := RunFile (t)
                else
                begin
                  RestorePos (P, L);  { not external function, go back }
                  { expression 'quote' X }
                  if s = 'quote' then
                  begin
                    s := GetToken (TRUE);
                    if s = 'atom' then
                      s := s + GetToken (TRUE);
                    if (s = ':') or (s[Length (s)] = '=') then
                      s := s + GetToken (TRUE);
                  end;
                  { none of the above, assume it is an atom value }
                  CheckMem (SizeOf (Tree));
                  GetMem (TmpTree, SizeOf (Tree));
                  ClearNode (TmpTree);
                  CheckMem (Length (s) + 1);
                  GetMem (TmpTree^.Value, Length (s) + 1);
                  TmpTree^.Value^ := s;
                  TmpTree^.Atom := TRUE;
                  ReadExpr := TmpTree;
                end  { else }
              end;  { else }
  end;  { ReadExpr }

  {
    The final 'write' statement of a WHILE program:
       -  level 0: write output value to screen
       -  level N: store output value in temporary variable in
                   level N - 1, _tmp_(N-1)
  }

  procedure WriteVar;
    { run 'write' statement }
    var
      VarName,
      Value,
      s: string;
      Tree: TreePtr;
  begin  { WriteVar }
    if Monitor then
      WriteLn;

    { parse variable to write }
    VarName := GetToken (TRUE);
    { variable name must start with capital letter }
    if not (VarName[1] in ['A'..'Z']) then
      Error ('Identifier expected.', Files[CurLevel].LastPos);

    { get current value of the variable }
    Tree := GetVar (VarName);

    if CurLevel = 0 then  { output to screen or stdout }
    begin
      Write (VarName, ': ');
      if LStrOut then
        WriteLongStr (WriteLTree (Tree, 1))
      else
      begin
        s := WriteTree (Tree, 1);
        if s[0] = #255 then  { line too long }
        begin
          Write (Copy (s, 1, 254));
          WriteLn ('...');
        end
        else
          WriteLn (s);
      end;  { else }
    end  { if }
    else  { store in parent's temporary variable _tmp_X }
    begin
      { parent's variables can only be accessed from level (CurLevel-1) }
      Dec (CurLevel);
      StoreVar (ResultVarName (CurLevel), Tree);
      Inc (CurLevel);
    end;  { else }

    { allow ';' after write statement }
    CheckToken (';');
  end;  { WriteVar }


  {
    The first 'read' statement of a WHILE program:
       -  level 0: read from keyboard or from data-file
       -  level N: read the parameters in parent's code
                   example:  X := filename.whl ( parameters );
                                                 ^
  }

  procedure ReadVar;
    { run 'read' statement }
    var
      VarName,
      Value,
      s: string;
      Tree: TreePtr;
      F: Text;
  begin  { ReadVar }
    { parse variable name }
    VarName := GetToken (TRUE);
    { variable name must start with capital letter }
    if not (VarName[1] in ['A'..'Z']) then
      Error ('Identifier expected.', Files[CurLevel].LastPos);

    if CurLevel = 0 then  { read from keyboard or from file }
    begin
      if WhileData <> '' then  { data file specified at command line }
      begin
        Assign (F, WhileData);
        Reset (F);
          { ** if IOResult <> 0 then ... ** }
        Value := '';
        { read data from file }
        Tree := ReadFileData (Value, F);
        Close (F);
          { ** if not Eof (F) then ... ** }
      end
      else  { read from keyboard }
      begin
        Write (VarName, ': ');
        ReadLn (Value);
        Tree := ReadTree (Value);  { convert string to tree }
      end;  { else }

      { if input was correct, ReadTree () should have 'eaten' the
        whole string, so Value must be empty }
      DelSpaces (Value);
      if Value <> '' then
        Abort ('Syntax error: ' + Value);

      StoreVar (VarName, Tree);
    end  { if }
    else  { read data from parameter in parent's code }
    begin
      Dec (CurLevel);  { go to parent's level }
      Tree := ReadExpr;  { parse parameters }
      Inc (CurLevel);

      StoreVar (VarName, Tree);
    end;  { else }
    Expect (';');
  end;  { ReadVar }

  procedure Assignment (VarName: string);
    { run assignment: VarName ':=' Expression }
    var
      s: string;
  begin  { Assignment }
    Expect (':=');
    StoreVar (VarName, ReadExpr);
    Expect (';');
  end;  { Assignment }

  function ConvAssignment (VarName: string): LongStrPtr;
    { convert assignment to WHILE-data }
    var
      s: string;
      lsp: LongStrPtr;
  begin  { ConvAssignment }
    { X := Y  =>  (:= (var #X) (Y)) }
    s := '(:= (var ' + ConvVar (VarName) + ') ';
    Expect (':=');
    LStrInit (lsp);
    LStrAddStr (lsp, s);
    LStrAddLStr (lsp, ConvExpr);  { parse the expression }
    LStrAddStr (lsp, ')');
    Expect (';');
    ConvAssignment := lsp;
  end;  { ConvAssignment }


  {
    The 'case' statement in WHILE automatically assignes values to
    variables in a structure that matches the expression, for example:

      case (X.Y) of
        (A.B) => ...

    Here, A is assigned to the value of X and B to the value of Y
    (this only happens with the matching case)
  }

  function ReadCaseTree: TreePtr;
    { read 'case' expression structure }
    var
      Root: TreePtr;
      Atom: string;
      L: Integer;
      s: string;
  begin  { ReadCaseTree: }
    s := GetToken (TRUE);

    { allow combined tokens ':=' and '=?' }
    if (s = ':') and (LookAheadChar = '=') then
      s := s + GetToken (TRUE);
    if (s = '=') and (LookAheadChar = '?') then
      s := s + GetToken (TRUE);

    if s = 'nil' then
      ReadCaseTree := nil
    else
    begin
      CheckMem (SizeOf (Tree));
      GetMem (Root, SizeOf (Tree));
      ClearNode (Root);
      if s = '(' then  { read a tree (recursive) }
      begin
        Root^.Atom := FALSE;
        Root^.Head := ReadCaseTree;
        Expect ('.');
        Root^.Tail := ReadCaseTree;
        Expect (')');
      end
      else  { read an atom }
      begin
        Atom := s;
        L := Length (Atom) + 1;
        CheckMem (L);
        GetMem (Root^.Value, L);
        Root^.Value^ := Atom;
        Root^.Atom := TRUE;
      end;  { else }
      ReadCaseTree := Root;
    end;  { else }

    { when tracing, show all steps }
    if Tracing then
      Trace;
  end;  { ReadCaseTree: }

  function CompareTree (E, T: TreePtr): Boolean;
    { compare two trees }
    var
      Tree: TreePtr;
  begin  { CompareTree }
    if T = nil then
      CompareTree := E = nil
    else
      if T^.Atom then  { compare atoms }
      begin
        if T^.Value^[1] in ['A'..'Z'] then
          CompareTree := TRUE
        else
          CompareTree := E^.Atom and (E^.Value^ = T^.Value^);
      end
      else  { compare branches }
        CompareTree := (not E^.Atom) and CompareTree (E^.Head, T^.Head) and
            CompareTree (E^.Tail, T^.Tail);
  end;  { CompareTree }

  procedure AssignTree (E, T: TreePtr);
    { assign values from E in T's variable names (case statement)
      E and T must have same structure (CompareTree (E, T) = TRUE) }
  begin  { AssignTree }
    if T <> nil then
    begin
      if T^.Atom then  { variable name }
      begin
        if T^.Value^[1] in ['A'..'Z'] then
          StoreVar (T^.Value^, E);
      end
      else  { follow trees }
      begin
        AssignTree (E^.Head, T^.Head);
        AssignTree (E^.Tail, T^.Tail);
      end;  { else }
    end;  { if }
  end;  { AssignTree }

  procedure RunCase;
    { run 'case' statement }
    var
      Depth, CompoundDepth: Integer;
      E, T: TreePtr;
      s: string;
      Match,
      Break: Boolean;
      NextCasePos,
      LastCasePos: PosRec;
  begin  { RunCase }
    { statement 'case' E 'of' E1 '=>' C; ... }
    with Files[CurLevel] do
    begin
      { save indent, needed to find end of case statement }
      Depth := LastPos.Pos;

      E := ReadExpr;
      Expect ('of');

      SavePos (NextCasePos, LastCasePos);  { next En to compare E with }
      Match := FALSE;
      Break := FALSE;
      repeat
        RestorePos (NextCasePos, LastCasePos);
        T := ReadCaseTree;   { ** T never cleared ** }
        Expect ('=>');
        CompoundDepth := LastPos.Pos;  { indent for compound }

        Match := (not Break) and CompareTree (E, T);
        if Match then
        begin
          AssignTree (E, T);
          Break := TRUE;  { match found, skip the rest }
        end;

        { compound statements may be enclosed in '(', ')' or indented }
        if CheckToken ('(') then
        begin
          CompoundDepth := 1;
          s := GetToken (TRUE);
          while ((s <> ')') or (CompoundDepth <> 0)) and (s <> #0) do
          begin
            if Match then
              Statement (s, nil);  { run statements }
            s := GetToken (TRUE);
            Inc (CompoundDepth, Byte (s = '(') - Byte (s = ')'));
          end;
          SavePos (NextCasePos, LastCasePos);
          s := GetToken (TRUE);
        end  { if }
        else  { indented compound }
        begin
          SavePos (NextCasePos, LastCasePos);
          s := GetToken (TRUE);
          while (LastPos.Pos > CompoundDepth) and (s <> #0) do
          begin
            if Match then
              Statement (s, nil);  { run statements }
            SavePos (NextCasePos, LastCasePos);
            s := GetToken (TRUE);
          end;
        end;  { else }

      until (LastPos.Pos <= Depth) or (s = #0);  { end of indented block }
      RestorePos (NextCasePos, LastCasePos);
    end;  { with }
  end;  { RunCase }

  function ConvWhile (const S1, S2, S3: string): LongStrPtr;
    { convert 'while' statement to WHILE-data (S1 = 'while', S2 = 'do'
      can also be used for 'if': S1 = 'if', S2 = 'then', S3 = 'else' }
    var
      lsp, lspBlock: LongStrPtr;
      s: string;
      Depth: Integer;
      ContinuePos, ContinueLast: PosRec;
  begin  { ConvWhile }
    { 'while' E 'do' C  =>  (while (E) (C))  or
      'if' E 'then' C1 'else' C2  =>  (if (E) (C1) (C2)) }
    LStrInit (lsp);
    with Files[CurLevel] do
    begin
      { save indent, needed to find end of case statement }
      Depth := LastPos.Pos;

      LStrAddStr (lsp, '(' + S1 + ' ');  { '(while ' or '(if ' }
      LStrAddLStr (lsp, ConvExpr);  { read expression E }
      Expect (S2);  { 'do' or 'then' }

      { convert the while/if-block of statements, must be indented }
      LStrInit (lspBlock);
      s := GetToken (TRUE);
      while (LastPos.Pos > Depth) and (s <> #0) do
      begin
        lspBlock := Statement (s, lspBlock);  { convert compound statments }
        SavePos (ContinuePos, ContinueLast);
        s := GetToken (TRUE);
      end;
      RestorePos (ContinuePos, ContinueLast);

      LStrAddStr (lsp, ' ');
      LStrAddLStr (lsp, lspBlock);

      if (S3 <> '') and CheckToken (S3) then  { 'else' }
      begin
        { convert else-block, must be indented too }
        LStrInit (lspBlock);
        s := GetToken (TRUE);
        while (LastPos.Pos > Depth) and (s <> #0) do
        begin
          lspBlock := Statement (s, lspBlock);
          SavePos (ContinuePos, ContinueLast);
          s := GetToken (TRUE);
        end;
        RestorePos (ContinuePos, ContinueLast);

        LStrAddStr (lsp, ' ');
        LStrAddLStr (lsp, lspBlock);
      end;  { if }

      LStrAddStr (lsp, ')');
    end;  { with }
    ConvWhile := lsp;
  end;  { ConvWhile }

  procedure RunWhile;
    { run 'while' statement }
    var
      s: string;
      Depth: Integer;
      Continue: Boolean;
      ExprPos, ExprLast,
      ContinuePos, ContinueLast: PosRec;
  begin  { RunWhile }
    { 'while' E 'do' C }
    with Files[CurLevel] do
    begin
      { save indent, needed to find end of case statement }
      Depth := LastPos.Pos;
      { save position of expression E, needed for evaluation again }
      SavePos (ExprPos, ExprLast);

      { continue while E not NIL }
      Continue := (ReadExpr <> nil) and (not CheckToken (#0));
      repeat
        Expect ('do');

        { compound statements may be enclosed in '(', ')' or indented }
        if CheckToken ('(') then
        begin
          Depth := 1;
          s := GetToken (TRUE);
          while ((s <> ')') or (Depth <> 0)) and (s <> #0) do
          begin
            if Continue then
              Statement (s, nil);  { run compound statements }
            s := GetToken (TRUE);
            Inc (Depth, Byte (s = '(') - Byte (s = ')'));
          end;
          SavePos (ContinuePos, ContinueLast);
        end  { if }
        else  { indented compound }
        begin
          s := GetToken (TRUE);
          SavePos (ContinuePos, ContinueLast);
          while (LastPos.Pos > Depth) and (s <> #0) do
          begin
            if Continue then
              Statement (s, nil);  { run compound statements }
            SavePos (ContinuePos, ContinueLast);
            s := GetToken (TRUE);
          end;
        end;  { else }
        RestorePos (ExprPos, ExprLast);
        Continue := (ReadExpr <> nil) and (not CheckToken (#0));
      until not Continue;
      RestorePos (ContinuePos, ContinueLast);
    end;  { with }
  end;  { RunWhile }


  function Statement (s: string; lspPrev: LongStrPtr): LongStrPtr;
    { run one WHILE statement, Statement () returns a LongStrPtr, this
      is only used when converting a program to WHILE-data }
    var
      lsp,
      lspTmp: LongStrPtr;
      Key: string[2];
      i, j: Integer;
    const
      LastY: Integer = 0;  { used to clear screen while watching variables }
  begin  { Statement }

    if KeyPressed then
    begin
      Key := GetKey;

      { Ctrl-C - start tracing }
      if Key = #3 then
      begin
        Tracing := TRUE;
        Monitor := FALSE;
      end;

      { Space - show variables once and continue }
      if (not Tracing) and (Key = ' ') and (not Monitor) then
        ListVars;

      { Tab - enter monitor mode, watch variables at run-time }
      if Key = #9 then
      begin
        Monitor := not Monitor;
        if Monitor then
        begin
          ClrScr;
          LastY := 1;
        end;
      end;
    end;  { if }

    if Monitor then
    begin
      { show variables }
      GoToXY (1, 1);
      ListVars;
      { clear rest of screen }
      ClrEol;
      j := WhereY;
      for i := j + 1 to LastY do
      begin
        GoToXY (1, i);
        ClrEol;
      end;
      LastY := j;
    end  { if }
    else
      if Tracing then
        Trace;

    { start tracing at a breakpoint, text 'break' in a WHILE-program }
    if s = 'break' then
    begin
      Tracing := TRUE;
      s := GetToken (TRUE);
    end;

    if Convert then  { -c option }
    begin
      LStrInit (lsp);

      if s = 'read' then
      begin
        { 'read' X  =>  '(var' #X ')' }
        LStrAddStr (lspStart, '((var ' + ConvVar ('') + ') ');
        Expect (';');
        lsp := lspPrev;
      end
      else
        if s = 'write' then
        begin
          { 'write' Y  =>  '(var' #Y ')' }
          LStrAddStr (lspEnd, ' (var ' + ConvVar ('') + '))');
          { allow ';' after write }
          CheckToken (';');
          lsp := lspPrev;
        end
        else
        begin

          { convert 'while' statement }
          if s = 'while' then
            lsp := ConvWhile ('while', 'do', '')
          else
            { the 'if' statement can be converted just like the 'while' }
            if s = 'if' then
              lsp := ConvWhile ('if', 'then', 'else')
            else
              { convert assignment }
              if not (s[1] in ['A'..'Z']) then
                Error ('Syntax error.', Files[CurLevel].LastPos)
              else
                lsp := ConvAssignment (s);

          { convert sequence of statements '(;' C1 ' ' C2 ')' }
          if (lspPrev <> nil) then
            if (LStrGetLen (lspPrev) > 0) then
            begin
             LStrInit (lspTmp);
             LStrAddStr (lspTmp, '(; ');
             LStrAddLStr (lspTmp, lspPrev);
             LStrAddStr (lspTmp, ' ');
             LStrAddLStr (lspTmp, lsp);
             LStrAddStr (lspTmp, ')');

             lsp := lspTmp;
 {             LStrInsertStr (lsp, '(;  ', 1);
              LStrInsertLStr (lsp, lspPrev, 4);
              LStrAddStr (lsp, ')');            }
            end;  { if }
        end;  { else }
    end  { if }
    else  { interpret statement }
      if s = 'read' then
        ReadVar
      else
        if s = 'write' then
          WriteVar
        else
          if s = 'while' then
            RunWhile
          else
            if s = 'case' then
              RunCase
            else
              if not (s[1] in ['A'..'Z']) then
                Error ('Syntax error.', Files[CurLevel].LastPos)
              else
                Assignment (s);

    Statement := lsp;
  end;  { Statement }

  var
    Filename: string;
    s: string;
    i: Integer;
    lsp: LongStrPtr;
    F: Text;
  {$IFDEF GARBAGE}
    M: LongInt;
  {$ENDIF}

begin  { WI }
{$IFDEF GARBAGE}
  { used to evaluate memory usage and garbage }
  M := MemAvail;
  LeastMem := M;
{$ENDIF}

  CurLevel := 0;  { start main program in level 0 }

  LastTraced := -1;
  TabSize := DEFAULT_TAB_SIZE;

  { read options and filenames from the command line }
  if not ReadCmdLine (Filename, WhileData) then
    ShowSyntax;
  AddExt (Filename, DEFAULT_EXTENSION);

  if not Quiet then
    ShowInfo;

  if not Exist (Filename) then
    Abort ('File not found: ' + Filename + '.');

  if Convert then
    if WhileData = '' then
    begin
      { no data file, use inputfile with '.dat' extension }
      WhileData := Filename;
      i := Pos ('.', WhileData);
      if i > 0 then
        Delete (WhileData, i, 255);
    end;

  if WhileData <> '' then
  begin
    AddExt (WhileData, DEFAULT_DATA_EXTENSION);
    if Convert then
    begin  { file WhileData will be used for output }
      if Exist (WhileData) and (not Overwrite) then
      begin
        Write ('File ' + WhileData + ' exists, overwrite (y/N)? ');
        if UpCaseStr (GetKey) <> 'Y' then
          Abort ('No')
        else
          WriteLn ('Yes');
      end;
    end
    else  { file WhileData will be used as input }
      if not Exist (WhileData) then
        Abort ('File not found: ' + WhileData + '.');
  end;  { if }

  { initialize source code buffer }
  GetMem (Source, SizeOf (Source^));
  for i := 0 to MAX_LINES - 1 do
    Source^[i] := nil;

  if not ReadFile (Filename, 0) then
    Abort ('Error reading file: ' + Filename + '.');

  { initialize variables }
  InitVars;

  lsp := nil;
  if Convert then
  begin
    if not Quiet then
    begin
      WriteLn;
      WriteLn ('Reading file ' + Filename + '...');
    end;
    LStrInit (lspStart);
    LStrInit (lsp);
    LStrInit (lspEnd);
  end;

  { run (or convert) program }
  s := GetToken (TRUE);
  while s <> #0 do
  begin
    lsp := Statement (s, lsp);
    s := GetToken (TRUE);
  end;

  if Convert then
  begin
    { write output to disk }
    LStrInsertLStr (lsp, lspStart, 1);
    LStrAddLStr (lsp, lspEnd);

    if not Quiet then
      Write ('Writing file ' + WhileData + '...');
    Assign (F, WhileData);
    ReWrite (F);
    { ** if IOResult <> 0 then ... ** }

    for i := 0 to LStrGetLen (lsp) - 1 do
      Write (F, Chr (lsp^[i + 2]));
    WriteLn (F);
    Close (F);

    if not Quiet then
      WriteLn;
  end;  { if }

  if FinalShow then
    ListVars;

  { dispose memory (Source[]) }
  for i := 0 to MAX_LINES - 1 do
    if Source^[i] <> nil then
    begin
      FreeMem (Source^[i], Length (Source^[i]^) + 1);
      Source^[i] := nil;
    end;
  FreeMem (Source, SizeOf (Source^));

  (*
  for i := 0 to MAX_VARIABLES - 1 do
  begin
    FreeTree (Values[i]);
    Values[i] := nil;
  end;
  *)

{$IFDEF GARBAGE}
  { show memory usage and garbage }
  if not Quiet then
  begin
    WriteLn;
    WriteLn ('[Info]: Total memory used: ', M - LeastMem,
        ' bytes, garbage: ', M - MemAvail, ' bytes.');
  end;
{$ENDIF}

end.  { WI }
