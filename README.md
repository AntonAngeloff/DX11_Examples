The motivation of this tutorial is do demonstrate some basic workflow 
of Direct3D 11 with FreePascal/Delphi, and how to start a very basic framework, since 
there are not much resources on the subject for this particular compiler and language 
group, and it can be rather hard to get started.

The samples are currently tested with FPC 3.0.1 (with Lazarus 1.4RC1) and Delphi XE5.

For any ideas, problems or suggestions please write to antonn.angelov at gmail.com.

Requirements (one of the following):
  - FPC 3.0.0 or higher version 
  - Delphi XE3 or higher

How to compile:
  - First you have to download the D3D11 header translations (see below)
  - Make sure the project sees the directory where the headers are located (this should be okay by default)
  - Open tutorial's project file 
    + For Lazarus/FPC - open the Lazarus Project Information file (.lpi) of the particular tutorial
    + For Delphi - open the Delphi Project file (.dpr). Each tutorial should contain both.
  
Header translations:
  - These examples are based on the translations provided by CMCHTPC @ https://github.com/CMCHTPC/DelphiDX12 . You have to download the headers from their original location before compiling the examples.
  - With some modification it should possible to make them compile with JSB or other translations.

TODO:
  - Write tutorials in a blog and put links here
  - Add another tutorial to demonstrate usage of a camera class and more generic model class
  - Add tutorial to demonstrate normal mapping, etcetra