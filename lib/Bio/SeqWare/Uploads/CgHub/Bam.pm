package Bio::SeqWare::Uploads::CgHub::Bam;

use 5.014;         # Eval $@ safe to use.
use strict;        # Don't allow unsafe perl constructs.
use warnings       # Enable all optional warnings
   FATAL => 'all';      # Make all warnings fatal.
use autodie;       # Make core perl die on errors instead of returning undef.
use Carp;          # User-space excpetions

use Getopt::Long;  # Parse command line options and arguments.
use Pod::Usage;    # Usage messages for --help and option errors.

use File::HomeDir qw(home);             # Finding the home directory is hard.
use File::Spec::Functions qw(catfile);  # Generic file handling.
use Data::GUID;                         # Unique uuids.

# GitHub only modules
use Bio::SeqWare::Config;   # Config file parsing.

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

    $self->loadOptions( $self->parseCli() );
    return $self;
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
    return 1;
}

=head1 INTERNAL METHODS

=head2 parseCli

    my $optHR = $obj->parseCli()

Parses the options and arguments from the command line into a hashref with the
option name as the key. Parsing is done with GetOpt::Long. Some options are
"short-circuit" options, if given all other options are ignored (i.e. --version
or --help). If an unknown option is provided on the command line, this will
exit with a usage message. For options see the OPTIONS section in
upload-cghub-bam.

=cut

sub parseCli {
    my $self = shift;

    # Values from config file (not implemented yet)
    my $configOptionsHR = {};

    # Default values
    my $optionDefaultsHR = {
        'config' => Bio::SeqWare::Config->getDefaultFile(),
    };

    # Combine local defaults with (over-ride by) config file options
    my %opt = ( %$optionDefaultsHR, %$configOptionsHR );

    # Record command line arguments
    $opt{'argv'} = [ @ARGV ];

    # Override local/config options with command line options
    GetOptions(

        # Input options.
        'config=s'   => \$opt{'config'},
        # Output options.
        'verbose'    => \$opt{'verbose'},
        'debug'      => \$opt{'debug'},

        # Short-circuit options.
        'version'      => sub {
            print "upload-cghub-bam v$VERSION\n";
            exit 1;
        },
        'help'         => sub {
            pod2usage( { -verbose => 1, -exitval => 1 });
        },

    ) or pod2usage( { -verbose => 0, -exitval => 2 });

    return \%opt;
}

=head2 getConfigOptions

    my %configOptHR = $self->loadConfig( $fileName );

Validates the filename as this is called early and the $fileName may be
an unvalidated options.

Returns a hash-ref of optionName => value entries.

Will die if can't find the config file specified, or if something happens
while parsing the config file (i.e. with Bio::Seqware::Config)

=cut

sub getConfigOptions {
    my $self = shift;
    my $fileName = shift;

    $fileName = $self->fixupTildePath( $fileName );
    unless (defined $fileName) {
        croak( "Can't find config file: <undef>." );
    }
    unless (-f $fileName) {
        croak( "Can't find config file: \"$fileName\"." );
    }

    my $configParser = Bio::SeqWare::Config->new( $fileName );
    return $configParser->getAll();
}

=head2 fixupTildePath

    my $path = $self->fixupTildePath( $filePath );

Perl does not recognize the unix convention that file paths begining with
a tilde (~) are relative to the users home directory. This is function makes
that happen *lexically*. There is no validation that the output file or path
actually makes sense. If the the input path does not begin with a ~, it is
returned without change. Uses File::HomeDir to handle finding a home dir.

=cut

sub fixupTildePath {
    my $self = shift;
    my $path = shift;

    unless ($path && $path =~ /^~/) {
        return $path;
    }

    my $home = home();
    $path =~ s/^~/$home/;
    return $path;
}

=head2 loadOptions

   $self->loadOptions({ key => value, ... });

Loads the provided key => value settings into the object. Returns nothing on
success. As this does validation, it can die with lots of different messages.
It also does cross-validation and fills in implicit options, i.e. it sets
--verbose if --debug was set.

=cut

sub loadOptions {
    my $self = shift;
    my $optHR = shift;

    if ($optHR->{'verbose'}) { $self->{'verbose'} = 1; }
    if ($optHR->{'debug'}) { $self->{'verbose'} = 1; $self->{'debug'} = 1; }

    $self->{'_optHR'} = $optHR;

}

=head2 sayDebug

   $self->sayDebug("Something printed only if --debug was set.");

Used to output text conditional on the --debug flag. Nothing is output if
--debug is not set.

See also say, sayVerbose.

=cut

sub sayDebug {
    my $self = shift;
    my $message = shift;
    unless ( $self->{'debug'} ) {
        return;
    }
    print( $message );
}

=head2 sayVerbose

   $self->sayVerbose("Something printed only if --verbose was set.");

Used to output text conditional on the --verbose flag. Nothing iw output if
--verbose was not set. Note setting --debug automatically implies --verbose,
so sayVerbose will output text when --debug was set even if --verbose never
was expcicitly passed 

See also say, sayDebug.

=cut

sub sayVerbose {
    my $self = shift;
    my $message = shift;
    unless ( $self->{'verbose'} ) {
        return;
    }
    print( $message );
}

=head2 say

   $self->say("Something to print regardless of --verbose and --debug");

Output text just like print, but wrapped so it is cognitively linked with
sayVerbose and sayDebug.

See also sayVerbose, sayDebug.

=cut

sub say {
    my $self = shift;
    my $message = shift;
    print( $message );
}

=head2 makeUuid

    my $uuid = $self->makeUuid();

Creates and returns a new unique string form uuid like
"A3865E1F-9267-4267-BE65-AAC7C26DE4EF".

=cut

sub makeUuid {
    my $self = shift;
    return Data::GUID->new()->as_string();
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
