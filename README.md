# NAME

Bio::SeqWare::Uploads::CgHub::Bam - Upload a bam file to CgHub

# VERSION

Version 0.000.001

# SYNOPSIS

    use Bio::SeqWare::Uploads::CgHub::Bam;

    my $obj = Bio::SeqWare::Uploads::CgHub::Bam->new();

# CLASS METHODS

## new()

    my $obj = Bio::SeqWare::Uploads::CgHub::Bam->new();

Creates and returns a Bio::SeqWare::Uploads::CgHub::Bam object. Either returns
an object of class Bio::Seqware::Uploads::CgHub::Bam or dies with an error
message.

# INSTANCE METHODS

## run()

    $obj->run()

Implements the actions taken when run as an application. Currently only
returns 1 if succeds, or dies with an error message.

## parseBamCli

    my $optHR = $obj->parseBamCli()

Parses the options and arguments from the command line into a hashref with the
option name as the key. Parsing is done with GetOpt::Long. Some options are
"short-circuit" options, if given all other options are ignored (i.e. --version
or --help).

- --version

    If specified, the version will be printed and the program will exit.

# AUTHOR

Stuart R. Jefferys, `<srjefferys (at) gmail (dot) com>`

Contributors:
  Lisle Mose (get\_sample.pl and generate\_cghub\_metadata.pl)
  Brian O'Conner

# DEVELOPMENT

This module is developed and hosted on GitHub, at
[https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam](https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam).
It is not currently on CPAN, and I don't have any immediate plans to post it
there unless requested by core SeqWare developers (It is not my place to
set out a module name hierarchy for the project as a whole :)

# INSTALLATION

You can install this module directly from github using cpanm

    # The latest bleeding edge commit on the main branch
    $ cpanm https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam

    # Any specific release:
    $ cpanm https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam/archive/v0.000.031.tar.gz

You can also download a release (zipped file) from github at
[https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Fastq/releases](https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Fastq/releases).

Installing is then a matter of unzipping it, changing into the unzipped
directory, and then executing the normal (`Module::Build`) incantation:

     perl Build.PL
     ./Build
     ./Build test
     ./Build install

# BUGS AND SUPPORT

No known bugs are present in this release. Unknown bugs are a virtual
certainty. Please report bugs (and feature requests) though the
Github issue tracker associated with the development repository, at:

[https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam/issues](https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam/issues)

Note: you must have a GitHub account to submit issues. Basic accounts are free.

# ACKNOWLEDGEMENTS

This module was developed for use with [SegWare ](https://metacpan.org/pod/&#x20;http:#seqware.github.io).

# LICENSE AND COPYRIGHT

Copyright 2014 Stuart R. Jefferys.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; version 2 dated June, 1991 or at your option
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

A copy of the GNU General Public License is available in the source tree;
if not, write to the Free Software Foundation, Inc.,
59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
