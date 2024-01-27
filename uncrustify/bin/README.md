# INTRODUCTION
This directory contains Perl scripts used to build the uncrustify documentation.

The information used to build this documentation is based on the output from:
- uncrustify --universalindent
- uncrustify --set &lt;option>=&lt;value>
- uncrustify --tracking &lt;type>:FILE

and on the **UDS files**.

### UDS files
The **U**ncrustify **D**ocumentation **S**cript (UDS) is a very simple text format that 
describes how to execute uncrustify to highlight the effects of an option.

### BUILD PROCESS

1) A default uds file is generated for each option.<br>
It is possible to modify or overwrite these files manually.

2) Each uds file is used to drive the execution of uncrustify.<br>
The output is parsed to create an html file.

3) Another html file is build for each option.<br>
This html file contains 3 sections:
   - The **properties** of the option: Categorie, Type, Default value.
   - A short **description** of the option.
   - **Examples** of the effects of the option on the code.

   The **properties** and the **description** are comming from the output of ```uncrustify --universalindent```

   The **examples** is an iframe including the html file generated based on the corresponding uds file.

   ```
    +-<html>----------------+
    | PROPERTIES            |
    |   ...                 |
    | DESCRIPTION           |
    |   ...                 |
    | EXAMPLES              |
    |   +<iframe>-------+   |
    |   | html file     |<---------- [uds file]
    |   |               |   |
    |   +</iframe>------+   |
    |                       |
    +-</html>---------------+

   ```
4)  Finally, indexes are built to facilitate access to this information.

### The hard work

The scripts in this directory are used to generate all the **html** files 
and the default **uds** files. But most of the time the **uds** file is not 
very good and need to be tuned or replaced **MANUALY**.

The hardest part is to provide a (short) code example that shows the effect 
of an option in various circumstances.

# Scripts

- For each options **generateDefaultUDS**.pl generates a default uds file.<br>
If an uds file, manually edited, already exist it is not modified.

- **generateExamples**.pl executes each uds file and generate and html file.<br>
These html files will be included by an &lt;iframe> in the **Example** section.

- For each option **generateUncrustifyOptions**.pl generates an html file with the three sections
(Properties, Description, Example) and generates the indexes (by name, by type, by categorie).<br>
If the html file required for the Example section is missing an explanatory message is inserted.


Each time an uds file is manually modified **generateExamples**.pl should be executed.
It is not require to executed **generateUncrustifyOptions**.pl .

Because executing **generateExamples**.pl is time consuming it will only execute an uds file 
if it is newer than the corresponding html. Use the --force option to force execution.

# File layout

~~~
 myGitPageHome
   +-> ...
   +-> uncrustify
        +-> index.html       Entry point in the uncrustify documentation
        +-> bin
        |    +-> *.pl        Perl scripts used to generated the various html and udc files
        +-> examples
        |    +-> *.html      html files showing effects of an option on code (auto generated)
        +-> options
        |     +-> *.html     html files describing options (auto generated)
        +-> uds
             +-> *.uds       udc files edited/tuned manualy (the hard work is here)
             +-> default
                  +-> *.uds  Default udc files (auto generated)

~~~