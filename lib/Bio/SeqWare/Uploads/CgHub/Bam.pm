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
use Getopt::Long;  # Parse command line options and arguments.
use Pod::Usage;    # Usage messages for --help and option errors.
use File::Spec::Functions qw(catfile);  # Generic file handling.
use IO::File ;     # File io using variables as fileHandles.
                   # Note: no errors on open failure.

# Cpan modules
use File::HomeDir qw(home);             # Finding the home directory is hard.
use Data::GUID;                         # Unique uuids.

# GitHub only modules
use Bio::SeqWare::Config;          # Config file parsing.
use Bio::SeqWare::Db::Connection;  # Database handle generation

my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';

my $COMMAND_DISPATCH_HR = {
    'select'        => \&do_select,
    'meta-generate' => \&do_meta_generate,
    'meta-validate' => \&do_meta_validate,
    'meta-upload'   => \&do_meta_upload,
    'file-upload'   => \&do_file_upload,
    'status-update' => \&do_status_update,
    'status-remote' => \&do_status_remote,
    'status-local'  => \&do_status_local,
};

=head1 NAME

Bio::SeqWare::Uploads::CgHub::Bam - Upload a bam file to CgHub

=head1 VERSION

Version 0.000.002

=cut

our $VERSION = '0.000002';

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

=head2 getUuid

    my $uuid = $self->getUuid();

Creates and returns a new unique string form uuid like
"A3865E1F-9267-4267-BE65-AAC7C26DE4EF".

=cut

sub getUuid {
    my $class = shift;
    return Data::GUID->new()->as_string();
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
    $COMMAND_DISPATCH_HR->{$self->{'command'}}(($self));
    return 1;
}

=head1 INTERNAL METHODS

=cut

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

    $self->{'id'} = $CLASS->getUuid();
    $self->{'dbh'} = undef; 
    my $cliOptionsHR = $self->parseCli();
    my $configFile = $cliOptionsHR->{'config'};
    my $configOptionsHR = $self->getConfigOptions( $configFile );
    my %opt = ( %$configOptionsHR, %$cliOptionsHR );
    $self->loadOptions( \%opt );
    $self->loadArguments( $opt{'argumentsAR'} );

    # Retrspectve logging (as logging being configured above.)
    $self->sayDebug("Loading config file:", $configFile);
    $self->sayDebug("Config options:", $configOptionsHR);
    $self->sayDebug("CLI options:", $cliOptionsHR);

    return $self;
}

=head2 DESTROY()

Called automatically upon destruction of this object. Should close the
database handle if opened by this class. Only really matters for error
exits. Planned exists do this manually.

=cut

sub DESTROY {
    my $self = shift;
    if ($self->{'dbh'}->{'Active'}) {
        unless ($self->{'dbh'}->{'AutoCommit'}) {
            $self->{'dbh'}->rollback();
        }
        $self->{'dbh'}->disconnect();
    }
}

=head2 parseCli

    my $optHR = $obj->parseCli()

Parses the options and arguments from the command line into a hashref with the
option name as the key. Parsing is done with GetOpt::Long. Some options are
"short-circuit" options (i.e. --version or --help). When encountered all
following options and argments will be ignored. Once all options are removed
from the command line, what remains are arguments. The presence of an unknown
option is an error. A stand-alone "--" prevents parsing anything following as
options, they will be used as arguments. This allows, for example, a filename
argument like "--config", however confusing that might be...

For a list of options see the OPTIONS section in upload-cghub-bam.

If no short circuit options and no parsing errors occur, will return a hash-ref
of all options, those not found having a value of undefined (including boolean
flags). In addition the following keys are present

=over 3

=item "_argvAR"

The original command line options and arguments, as an array ref.

=item "_argumentsAR"

The arguments left after parsing options out of the command line, as an array ref.

=back

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

        # Db connection options
        'dbUser=s'     => \$opt{'dbUser'},
        'dbPassword=s' => \$opt{'dbPassword'},
        'dbHost=s'     => \$opt{'dbHost'},
        'dbSchema=s'   => \$opt{'dbSchema'},

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

    my @arguments = @ARGV;

    $opt{'argumentsAR'} = \@arguments;

    return \%opt;
}

=head2 parseSampleFile 

    my sampleDataRecords = $self->parseSampleFile()

Read a tab delimited sample file and for each non-comment, non-blank,
non header line, include a record of data in the returned array (ref) of
samples. Each line in order will be represented by a hash (ref) with the keys
'sample', 'flowcell', 'lane', and 'barcode'. If additional columns are present
in the file, a header line is required.

If a header is provided it must start with sample\tflowcell\tlane\tbarcode
This way, each record will have an entry for each column, keyed by column name.

If the first line in a file looks like a header (i.e it contains the text
'sample' and 'flowcell' in that order, than it MUST be a real header line.

=cut

sub parseSampleFile {

    my $self = shift;

    my $inFH = IO::File->new("< $self->{'sampleFile'}");
    if (! $inFH) {
        croak( "Can't open sample file for reading: \"$self->{'sampleFile'}\".\n$!\n");
    }

    my @rows;
    my $lineNum = 0;
    my $isFirstLine = 1;
    my $fieldDelim = qr/[ ]*\t[ ]*/;
    my @headings = qw( sample flowcell lane barcode );

    while ( my $line = <$inFH> ) {
        ++$lineNum;
        chomp $line;
        next if ( $line =~ /^\s*$/ );  # Blank line
        next if ( $line =~ /^\s*#/ );  # Comment line

        my @fields = split( $fieldDelim, $line, -1);
        if ($isFirstLine) {
            $isFirstLine = 0;

            # Handle first real line is header
            if ($line =~ /^sample\tflowcell\tlane\tbarcode.*/) {
                @headings = @fields;
                my %dupHeaderCheck;
                for my $fieldName (@headings) {
                    if (length $fieldName < 1 ) {
                        croak "Sample file header can not have empty fields: \"$self->{'sampleFile'}\".\n";
                    }
                    if (exists $dupHeaderCheck{"$fieldName"}) {
                        croak "Duplicate headings not allowed: \"$fieldName\" in sample file \"$self->{'sampleFile'}\".\n" 
                    }
                    else {
                        $dupHeaderCheck{"$fieldName"} = 1;
                    }
                 }
                 next;
            }
            # Handle first real line is defective header
            elsif ($line =~ /.*sample.*flowcell.*/) {
                croak "Looks like sample file has a bad header line: \"$self->{'sampleFile'}\".\n";
            }
            # Drop through to handle first line is data line.
        }

        # Handle data line.

        if (scalar @fields < scalar @headings ) {
            croak "Missing data from line $lineNum in file \"$self->{'sampleFile'}\". Line was:\n\"$line\"\n";
        }
        if (scalar @fields > scalar @headings ) {
            croak "More data than headers: line $lineNum in sample file \"$self->{'sampleFile'}\". Line was:\n\"$line\"\n";
        }
        my $lineHR;
        for( my $col = 0; $col < scalar @fields; $col++) {
            $lineHR->{"$headings[$col]"} = $fields[$col];
        }
        push @rows, $lineHR;

    } # Iterate over every line in $self->{'sampleFile'}.

    return \@rows;
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
    $self->{'_argvAR'} = $optHR->{'argvAR'};
    $self->{'_argumentsAR'} = $optHR->{'argumentsAR'};

    unless ( $optHR->{'dbUser'}    ) { croak("--dbUser option required."    ); };
    unless ( $optHR->{'dbPassword'}) { croak("--dbPassword option required."); };
    unless ( $optHR->{'dbHost'}    ) { croak("--dbHost option required."    ); };
    unless ( $optHR->{'dbSchema'}  ) { croak("--dbSchema option required."  ); };

    $self->{'dbUser'}     = $optHR->{'dbUser'};
    $self->{'dbPassword'} = $optHR->{'dbPassword'};
    $self->{'dbHost'}     = $optHR->{'dbHost'};
    $self->{'dbSchema'}   = $optHR->{'dbSchema'};
}

=head2 loadArguments

   $self->loadArguments(["arg1", "arg2"]);

Valdates and loads the CLI arguments (What is left over after removing options
up to and including a lone "--"). Returns nothing on success. As this does
validation, it can die with lots of different messages.

=cut

sub loadArguments {
    my $self = shift;
    my $argumentsAR = shift;
    my @arguments = @{$argumentsAR};

    my $command = shift @arguments;
    unless( defined $command ) {
        croak "Must specify a command. Try --help.\n";
    }
    unless(exists $COMMAND_DISPATCH_HR->{"$command"}) {
        croak "I don't know the command '$command'. Try --help.\n";
    }
    $self->{'command'} = $command;

    my $sampleFile = shift @arguments;
    if (defined $sampleFile) {
        unless( -f $sampleFile ) {
            croak "I can't find the sample file '$sampleFile'.\n";
        }
    }
    $self->{'sampleFile'} = $sampleFile;   # May be undefined

    if (@arguments) {
        croak "Too many arguments for cammand '$command'. Try --help.\n";
    }

    return 1;
}

=head2 do_select

Called automatically by runner framework to implement the select command.
Not intended to be called directly.

=cut

sub do_select {
    return 1;
}

=head2 do_meta_generate

Called automatically by runner framework to implement the meta-generate command.
Not intended to be called directly.

=cut

sub do_meta_generate {
    return 1;
}

=head2 do_meta_validate

Called automatically by runner framework to implement the meta-validate command.
Not intended to be called directly.

=cut

sub do_meta_validate {
    return 1;
}

=head2 do_meta_upload

Called automatically by runner framework to implement the meta-upload command.
Not intended to be called directly.

=cut

sub do_meta_upload {
    return 1;
}

=head2 do_file_upload

Called automatically by runner framework to implement the file_upload command.
Not intended to be called directly.

=cut

sub do_file_upload {
    return 1;
}

=head2 do_status_update

Called automatically by runner framework to implement the status-update command.
Not intended to be called directly.

=cut

sub do_status_update {
    return 1;
}

=head2 do_status_remote

Called automatically by runner framework to implement the status-remote command.
Not intended to be called directly.

=cut

sub do_status_remote {
    return 1;
}

=head2 do_status_local

Called automatically by runner framework to implement the status-local command.
Not intended to be called directly.

=cut

sub do_status_local {
    return 1;
}

=head2 getDbh

  my $dbh = $self->getDbh();

Returns a cached database handle, create and cahcing a new one first if not
already existing. Creating requires appropriate parameters to be set and can
fail with a "DbConnectionException:...";

=cut

sub getDbh {
    my $self = shift;

    if ($self->{'dbh'}) {
        return $self->{'dbh'};
    }
    my $dbh;
    my $connectionBuilder = Bio::SeqWare::Db::Connection->new( $self );
    $dbh = $connectionBuilder->getConnection(
         {'RaiseError' => 1, 'PrintError' => 0, 'AutoCommit' => 1, 'ShowErrorStatement' => 1}
    );
    if (! defined $dbh) {
        croak "DbConnectException: Failed to connect to the database.\n";
    }

    $self->{'dbh'} = $dbh;
    return $dbh;
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
   $ cpanm https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam/archive/v0.000.002.tar.gz

You can also manually download a release (zipped file) from github at
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
