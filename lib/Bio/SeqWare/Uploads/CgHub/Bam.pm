package Bio::SeqWare::Uploads::CgHub::Bam;

use 5.014;         # Eval $@ safe to use.
use strict;        # Don't allow unsafe perl constructs.
use warnings       # Enable all optional warnings
   FATAL => 'all';      # Make all warnings fatal.
use autodie;       # Make core perl die on errors instead of returning undef.

# Core modules
use Carp;          # User-space excpetions
use Data::Dumper;  # Simple data structure to string converter.
use Sys::Hostname; # Get the hostname for logging

# Cpan modules
use Getopt::Long;  # Parse command line options and arguments.
use Pod::Usage;    # Usage messages for --help and option errors.

use File::HomeDir qw(home);             # Finding the home directory is hard.
use File::Spec::Functions qw(catfile);  # Generic file handling.
use Data::GUID;                         # Unique uuids.

# GitHub only modules
use Bio::SeqWare::Config;   # Config file parsing.

my
 $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';

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
message. Will initialize and validate options.

=cut

sub new {
    my $class = shift;
    my $paramHR = shift;

    my $self = {};
    bless $self, $class;

    return $self->init();
}

=head2 getTimestamp()

    Bio::SeqWare::Uploads::CgHub::Bam->getTimeStamp().
    Bio::SeqWare::Uploads::CgHub::Bam->getTimeStamp( $unixTime ).

Returns a timestamp formated like YYYY-MM-DD_HH:MM:SS, zero padded, 24 hour
time. If a parameter is passed, it is assumed to be a unix epoch time (integer
or float seconds since Unix 0). If no parameter is passed, the current time will
be queried. Time is parsed through perl's localtime().

=cut

sub getTimestamp {
    my $class = shift;
    my $time = shift;
    if (! defined $time) {
       $time = time();
    }
    my ($sec, $min, $hr, $day, $mon, $yr) = localtime($time);
    return sprintf ( "%04d-%02d-%02d_%02d:%02d:%02d",
                     $yr+1900, $mon+1, $day, $hr, $min, $sec);
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

=head2 init()

    my $self->init();

Sets up internal object data by loading cli options (including the config
filename) then loading the config file options and laying the cli options
over them. The combined options (hashref) is then passed to loadOptions which
does the validation and sets the final state of the internal object data.

Returns the fully initialized application object ready for running.

=cut

sub init {
    my $self = shift;

    $self->{'id'} = $self->makeUuid();
    my $cliOptionsHR = $self->parseCli();
    my $configFile = $cliOptionsHR->{'config'};
    my $configOptionsHR = $self->getConfigOptions( $configFile );
    my %opt = ( %$configOptionsHR, %$cliOptionsHR );
    $self->loadOptions( \%opt );

    # Retrspectve logging (as logging being configured above.)
    $self->sayDebug("Loading config file:", $configFile);
    $self->sayDebug("Config options:", $configOptionsHR);
    $self->sayDebug("CLI options:", $cliOptionsHR);

    return $self;
}

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

    # Default values
    my %opt = (
        'config' => Bio::SeqWare::Config->getDefaultFile(),
    );

    # Record copy of command line arguments.
    my @argv = @ARGV;
    $opt{'argvAR'} = \@argv;

    # Override local/config options with command line options
    GetOptions(

        # Input options.
        'config=s'   => \$opt{'config'},

        # Output options.
        'verbose'    => \$opt{'verbose'},
        'debug'      => \$opt{'debug'},
        'log'        => \$opt{'log'},

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

Valdates and loads the provided key => value settings into the object.
Returns nothing on success. As this does validation, it can die with lots of
different messages. It also does cross-validation and fills in implicit options, i.e. it sets
--verbose if --debug was set.

=cut

sub loadOptions {
    my $self = shift;
    my $optHR = shift;

    if ($optHR->{'verbose'}) { $self->{'verbose'} = 1; }
    if ($optHR->{'debug'}  ) { $self->{'verbose'} = 1; $self->{'debug'} = 1; }
    if ($optHR->{'log'}    ) { $self->{'log'}     = 1; }

    $self->{'_optHR'} = $optHR;
    $self->{'_argvAR'} = $optHR->{'argvAR'}

}

=head2 getLogPrefix

    my $prefix = $self->getLogPrefix()

Create a prefix for logging messages, formatted as

     HOST TIMESTAMP RUN-UUID [LEVEL]

where timestamp formatted like getTimestamp, described herein and level is the
reporting level (INFO by default, or VERBOSE or DEBUG, if --verbose or --debug
reporting is specified by option.)

=cut

sub getLogPrefix {
    my $self = shift;

    my $host = hostname();
    my $timestamp = $CLASS->getTimestamp();
    my $id = $self->{'id'};
    my $level = 'INFO';
    if ($self->{'verbose'}) {
        $level = 'VERBOSE';
    }
    if ($self->{'debug'}) {
        $level = 'DEBUG';
    }
    return "$host $timestamp $id [$level]";
}

=head2 logifyMessage

    my $logMessage = logifyMessage( $message );

Makes a message suitable for logging. It adds a prefix at the start of
every line and ensures the message ends with a newline. The prefix is by
provided by getLogPrefix. The prefix is separated from the message by a single
space, although any formating at the begining of a line is preserved, just
moved over by the length of the prefix (+ a space.)

=cut

sub logifyMessage {
    my $self = shift;
    my $message = shift;

    chomp $message;
    my @lines = split( "\n", $message, 0);
    my $prefix = $self->getLogPrefix() . " ";
    $message = $prefix . join( "\n$prefix", @lines);
    return $message . "\n";
}

=head2 sayDebug

   $self->sayDebug("Something printed only if --debug was set.");
   $self->sayDebug("Something" $object );

Used to output text conditional on the --debug flag. Nothing is output if
--debug is not set.

If the --log option is set, adds a prefix to each line of a message
using logifyMessage.

If an object parameter is passed, it will be printed on the following line.
Normal stringification is performed, so $object can be anything, including
another string, but if it is a hash-ref or an array ref, it will be formated
with Data::Dumper before printing.
 
See also say, sayVerbose.

=cut

sub sayDebug {
    my $self = shift;
    my $message = shift;
    my $object = shift;
    unless ( $self->{'debug'} ) {
        return;
    }
    if (ref $object eq 'HASH' or ref $object eq 'ARRAY') {
        $message = $message . "\n" . Dumper($object);
    }
    elsif (defined $object) {
        $message = $message . "\n" . $object;
    }

    if ( $self->{'log'} ) {
        $message = $self->logifyMessage($message);
    }
    print $message;
}

=head2 sayVerbose

   $self->sayVerbose("Something printed only if --verbose was set.");
   $self->sayVerbose("Something", $object);

Used to output text conditional on the --verbose flag. Nothing iw output if
--verbose was not set. Note setting --debug automatically implies --verbose,
so sayVerbose will output text when --debug was set even if --verbose never
was expcicitly passed 

If the --log option is set, adds a prefix to each line of a message
using logifyMessage.

If an object parameter is passed, it will be printed on the following line.
Normal stringification is performed, so $object can be anything, including
another string, but if it is a hash-ref or an array ref, it will be formated
with Data::Dumper before printing.

See also say, sayDebug.

=cut

sub sayVerbose {
    my $self = shift;
    my $message = shift;
    my $object = shift;
    unless ( $self->{'verbose'} ) {
        return;
    }
    if (ref $object eq 'HASH' or ref $object eq 'ARRAY') {
        $message = $message . "\n" . Dumper($object);
    }
    elsif (defined $object) {
        $message = $message . "\n"  . $object;
    }

    if ( $self->{'log'} ) {
        $message = $self->logifyMessage($message);
    }
    print $message;
}

=head2 say

   $self->say("Something to print regardless of --verbose and --debug");
   $self->say("Something", $object);

Output text like print, but takes object option like sayVerbose and
sayDebug.


If the --log option is set, adds a prefix to each line of a message
using logifyMessage.

If an object parameter is passed, it will be printed on the following line.
Normal stringification is performed, so $object can be anything, including
another string, but if it is a hash-ref or an array ref, it will be formated
with Data::Dumper before printing.
See also sayVerbose, sayDebug.

=cut

sub say {
    my $self = shift;
    my $message = shift;
    my $object = shift;
    if (ref $object eq 'HASH' or ref $object eq 'ARRAY') {
        $message = $message . "\n" . Dumper($object);
    }
    elsif (defined $object) {
        $message = $message . "\n"  . $object;
    }

    if ( $self->{'log'} ) {
        $message = $self->logifyMessage($message);
    }
    print $message;
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

This module was developed for use with L<SeqWare | http://seqware.github.io>.

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
