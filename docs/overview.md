---
updated: 2026-09-28
---

# Caracal Language Overview

Caracal is an imperative, compiled language with a focus on simple and enjoyable syntax. It is designed to be statically typed while still feeling ergonomic through type inference. 

> **Note**
> Everything from syntax to semantics is work-in-progress and may change. 
> This document describes the language **as the compiler implements it today**.
> Sections with `//TODO` are planned but not implemented yet.

## Table of contents

- [A first look](#a-first-look)
  - [Hello, world](#hello-world)
  - [Language tour](#language-tour)
  - [Syntax summary](#syntax-summary)
- [Compiling](#compiling)
  - [Debug and release modes](#debug-and-release-modes)
- [Basics](#basics)
  - [Source encoding](#source-encoding)
  - [Comments](#comments)
  - [Identifiers](#identifiers)
  - [Keywords](#keywords)
  - [Literals](#literals)
  - [Typed literals](#typed-literals)
  - [Semicolons](#semicolons)
  - [Order independent declarations](#order-independent-declarations)
- [More stuff](#more-stuff)

# A first look

## Hello, world

```cara
def main() i32
{
    // C.puts is temporary until we got a print function
    C.puts("Hello, world!");
    return 0;
}
```

The main function is the program's entry point, it needs to return an integer at the end.

## Language tour

```cara
// We can declare global constants, global variables however are not allowed
Version :: 3;

// Enums are scoped constants, they are similar to C enums
enum Level : i32
{
    Low    :: 1
    Medium :: 2
    High   :: 3
}

def main() i32
{
    // Constructing an object of type Counter with a named argument
    counter := Counter.new(start = 0);
    // Parenthesis for control flow is optional
    while !counter.atLimit()
    {
        counter.increment();
        skip if counter.value == 3;         // skip with trailing if
        break if counter.value > 8;             
    }

    // We declare variables with infered types using the := symbols
    numbers := [1, 2, 3, 4];                // fixed array of type [i32; 4]
    total := 0;
    i := 0;
    while i < numbers.length
    {
        // Arithmethic operations with a leading % allow for overflow/underflow
        total = total %+ numbers.at(i);
        i = i %+ 1;
    }

    // We evaluate the function but discard the result
    _ := describe(Level.High);
    return total %+ counter.value %+ Version;
}

// We can give parameters default values with the = symbol
def describe(level: Level, prefix: string = "level") i32
{
    return prefix.length() %+ 1 if level == Level.High;
    return prefix.length();
}

type Counter(start: i32)
{
    // Fields are required to be initialized, either with a literal or type parameter
    value := start
    limit : i32 : 10                        // Constant with explicit type

    def increment()
    {
        // We access fields with a leading dot, there is no this keyword like in other languages
        .value = .value %+ 1;
    }

    def atLimit() bool
    {
        return .value >= .limit;
    }
}
```

## Syntax summary

```
// declarations
name :: value;                        // constant
name : Type : value;                  // constant, explicit type
name := value;                        // variable (local only)
name : Type = value;                  // variable, explicit type
name :: init Type;                    // write-once global
_ :: expression;                      // discard

def name(a: T, b: U = default) R { }  // function
def Type.name(a: T) R { }             // static method
#extern(symbol = "s") def f() R {}    // extern

type Name(params) { fields methods }  // type
enum Name : Base { Members }          // enum

// types
bool i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 rune cstring rawptr string void
ref T          // reference
[T; N]         // fixed array
[T; _]         // dynamic array
[T]            // slice

// expressions
a %+ b   a %- b   a %* b   a / b
-a       !a       ref a
a == b   a != b   a < b   a <= b   a > b   a >= b
a and b  a or b
f(x, name = y)   obj.field   obj.method()   .field   Type.new()   Type.member
42'i32   1.5'f32   82'rune   "text"   true   false
[1, 2, 3]   [1, 2, ...]   [...]

// statements
if cond { } else if cond { } else { }
while cond { }
break;   skip;   return;   return value;
break if cond;   skip if cond;   return value if cond;
```

# Compiling

The compiler can currently only run one file with the following cli command. Dependencies like the standard library are automatically pulled in.

```
Caracal.exe path/to/program.cara
```

## Debug and release modes

//TODO

# Basics

## Source encoding

Source files have to be valid UTF-8 with or without a BOM, other encodings are rejected.

## Comments

```cara
// Line comment, runs to the end of the line.

/* Block comment,
   spans lines. */
```

## Identifiers

Identifiers can contain ASCII letters, numbers and underscores but are not allowed to start with a number.
A single underscore is not an identifier, its a [discard](#discards).

## Keywords

```cara
def     // function and method declarations
type    // type declarations
enum    // enum declarations
if      // if control flow
else    // else branch
while   // while control flow
break   // breaking out of blocks 
skip    // skipping the rest of blocks
return  // returning data
ref     // taking references or 
and     // logical and
or      // logical or
true    // boolean true literal
false   // boolean false literal
init    // contextual keyword for global init constants
new     // contextual keyword for creating instances
```

## Literals

```cara
awesome := true;                     // boolean literal
value   := 67;                       // i32 by default
pi      := 1.5;                      // f32 by default
hello   := "Hello, caracal 🐈!";    // utf-8 string
```

## Typed literals

Literals can be explicitly typed with a suffix.

```cara
value  := 42'i32;
byte   := 200'u8;
big    := 9000000000'i64;
ratio  := 1.5'f32;
letter := 82'rune;
```

## Semicolons

Statements generally have to end with a `;`. There are a few places where semicolons are not needed, for example between enum members or type fields.

```cara
enum Values
{
    First
    Second
}

type Vector2D(x: f32, y: f32)
{
    x := x
    y := y
}
```

## Order independent declarations

The order of declarations doesn't matter, you can use functions, enums and types before they are declared. Forward declarations arent needed either, the compiler collects whatever it needs on it's own.

```cara
def make() Number
{
    return Number.new(7);
}

type Number(value: i32)
{
    value := value
}
```

# More stuff

//TODO
