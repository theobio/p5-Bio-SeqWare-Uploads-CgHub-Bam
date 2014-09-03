package Bio::SeqWare::Uploads::CgHub::Bam;

use 5.014;         # Eval $@ safe to use.
use strict;        # Don't allow unsafe perl constructs.
use warnings       # Enable all optional warnings
   FATAL => 'all';      # Make all warnings fatal.
use autodie;       # Make core perl die on errors instead of returning undef.

use Getopt::Long;  # Parse command line options and arguments.


=head1 NAME

Bio::SeqWare::Uploads::CgHub::Bam - Upload a bam file to CgHub

=head1 VERSION

Version 0.000.001

=cut

our $VERSION = '0.000001';

=head1 SYNOPSIS

    use Bio::SeqWare::Uploads::CgHub::Bam;

    my $obj = Bio::SeqWare::Uploads::CgHub::Bam->new();

=cut

=head1 CLASS METHODS

=cut

=head2 new()

    my $obj = Bio::SeqWare::Uploads::CgHub::Bam->new();

Creates and returns a Bio::SeqWare::Uploads::CgHub::Bam object. Either returns
an object of class Bio::Seqware::Uploads::CgHub::Bam or dies with an error
message.

=cut

sub new {
    my $class = shift;
    my $paramHR = shift;

    my $self = {};
    bless $self, $class;
}

=head1 INSTANCE METHODS

=cut

=head2 run()

    $obj->run()

Implements the actions taken when run as an application. Currently only
returns 1 if succeds, or dies with an error message.

=cut

sub run {
    my $self = shift;
    my $opt = parseBamCli();
    return 1;
}

=head2 parseBamCli

    my $optHR = $obj->parseBamCli()

Parses the options and arguments from the command line into a hashref with the
option name as the key. Parsing is done with GetOpt::Long. Some options are
"short-circuit" options, if given all other options are ignored (i.e. --version
or --help).

=over 3

=item --version

If specified, the version will be printed and the program will exit.

=back

=cut

sub parseBamCli {
    my $self = shift;

    # Values from config file (not implemented yet)
    my $configOptionsHR = {};

    # Default values (not implemented yet)
    my $optionsHR = {};

    # Combine local defaults with (over-ride by) config file options
    my %opt = ( %$optionsHR, %$configOptionsHR );

    # Record command line arguments
    $opt{'argv'} = [ @ARGV ];

    # Override local/config options with command line options
    GetOptions(

        # Short-circuit options.
        'version'      => sub {
            print "upload-cghub-bam v$VERSION\n";
            exit 1;
        },

    );

    return \%opt;
}

=head1 AUTHOR

Stuart R. Jefferys, C<< <srjefferys (at) gmail (dot) com> >>

Contributors:
  Lisle Mose (get_sample.pl and generate_cghub_metadata.pl)
  Brian O'Conner

=cut

=head1 DEVELOPMENT

This module is developed and hosted on GitHub, at
L<https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam>.
It is not currently on CPAN, and I don't have any immediate plans to post it
there unless requested by core SeqWare developers (It is not my place to
set out a module name hierarchy for the project as a whole :)

=cut

=head1 INSTALLATION

You can install this module directly from github using cpanm

   # The latest bleeding edge commit on the main branch
   $ cpanm https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam

   # Any specific release:
   $ cpanm https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam/archive/v0.000.031.tar.gz

You can also download a release (zipped file) from github at
L<https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Fastq/releases>.

Installing is then a matter of unzipping it, changing into the unzipped
directory, and then executing the normal (C<Module::Build>) incantation:

     perl Build.PL
     ./Build
     ./Build test
     ./Build install

=cut

=head1 BUGS AND SUPPORT

No known bugs are present in this release. Unknown bugs are a virtual
certainty. Please report bugs (and feature requests) though the
Github issue tracker associated with the development repository, at:

L<https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam/issues>

Note: you must have a GitHub account to submit issues. Basic accounts are free.

=cut

=head1 ACKNOWLEDGEMENTS

This module was developed for use with L<SegWare | http://seqware.github.io>.

=cut


=head1 LICENSE AND COPYRIGHT

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

=cut

1; # End of Bio::SeqWare::Uploads::CgHub::Bam
