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
use Scalar::Util qw( blessed );  # Get class of objects
use File::Path;    # Create file paths

# Cpan modules
use File::HomeDir qw(home);     # Finding the home directory is hard.
use File::Share qw(dist_dir);   # Access data files from install.
use Data::GUID;                 # Unique uuids.
use Template;                   # Template files + data => output files.

# GitHub only modules
use Bio::SeqWare::Config;          # Config file parsing.
use Bio::SeqWare::Db::Connection;  # Database handle generation

my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';

my $COMMAND_DISPATCH_HR = {
    'launch'        => \&do_launch,
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

Version 0.000.003

=cut

our $VERSION = '0.000003';

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

    Bio::SeqWare::Uploads::CgHub::Bam->getTimestamp().
    Bio::SeqWare::Uploads::CgHub::Bam->getTimestamp( $unixTime ).

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

=head2 getErrorName

    my $errorName = $CLASS->getErrorName( "SomeException: An error occured" );

Extract the error or exception name from the first word in a string, assuming
that word ends in exception or error (any case). The name is the preceeding
part, i.e. "Some" for the string above. If no string can be determined (i.e.)
the first word is not "*exception" or "*error", then the name will be Unknown.

=cut

sub getErrorName {
    my $class = shift;
    my $errorString = shift;

    my $errorName = "Unknown";
    if ($errorString =~ m/^([^\s]+)(Exception|Error)/i) {
        $errorName = $1;
    }

    return $errorName;
}

=head2 ensureIsDefined

    my $val = $CLASS->ensureDefined( $val, [$error] );

Returns $val if it is defined, otherwise dies with $error. If $error is not
defined, then dies with error message:

    "ValidationErrorNotDefined: Expected a defined value.\n";

=cut

sub ensureIsDefined {
    my $class = shift;
    my $value = shift;
    my $error = shift;
    if (! defined $value) {
        if (! defined $error) {
            $error = "ValidationErrorNotDefined: Expected a defined value.\n"
        }
        die $error;
    }

    return $value
}

=head2 ensureHashHasValue

    my $val = $CLASS->ensureHashHasValue( $hashRef, $key, [$error] );

Returns $hashRef->{"$key"} if it is defined, otherwise dies with $error.
If $error is not defined, then dies with an appropriate message, one of:

    "ValidationErrorNotDefined: Expected a defined hash/hash-ref.\n";
    "ValidationErrorNotExists: Expected key $key to exist.\n";
    "ValidationErrorNotDefined: Expected a defined hash/hash-ref value for key $key.\n";
=cut

sub ensureHashHasValue {
    my $class = shift;
    my $hashHR = shift;
    my $key = shift;
    my $error = shift;

    if (! defined $hashHR) {
        if (! defined $error) {
            $error = "ValueNotDefinedException: Expected a defined hash/hash-ref.\n";
        }
        die $error;
    }
    if (ref( $hashHR ) ne 'HASH') {
        if (! defined $error) {
            $error = "ValueNotHashRefException: Expected a hash-ref.\n";
        }
        die $error;
    }
    if (! exists $hashHR->{"$key"}) {
        if (! defined $error) {
            $error = "KeyNotExistsException: Expected key $key to exist.\n";
        }
        die $error;
    }
    if (! defined $hashHR->{"$key"}) {
        if (! defined $error) {
            $error = "ValueNotDefinedException: Expected a defined hash/hash-ref value for key $key.\n"
        }
        die $error;
    }

    return $hashHR->{"$key"};
}

=head2 ensureIsntEmptyString

    my $val = $CLASS->ensureIsntEmptyString( $val, [$error] );

Returns $val if, stringified, it is not an empty string. Otherwise dies with
$error. If $error is not defined, then dies with error message:

    "ValidationErrorBadString: Expected a non-empty string.\n";

=cut

sub ensureIsntEmptyString {
    my $class = shift;
    my $value = shift;
    my $error = shift;

    if (! defined $value || length $value < 1) {
        if (! defined $error) {
            $error = "ValidationErrorBadString: Expected a non-empty string.\n";
        }
        die $error;
    }
    return $value
}

=head2 ensureIsFile

    my $filename = $CLASS->ensureIsFile( $filename, [$error] );

Returns $filename if it is defined and -f works, otherwise dies with $error.
If $error is not defined, then dies with error message:

    "ValueNotDefinedException: Expected a defined value.\n";
    "FileNotFoundException: Error looking up file named $filename. Error was:\n\t$!";

=cut

sub ensureIsFile {
    my $class = shift;
    my $filename = shift;
    my $error = shift;
    if (! defined $filename) {
        if (! defined $error) {
            $error = "ValueNotDefinedException: Expected a defined value.\n";
        }
        die $error;
    }
    if (! -f $filename) {
        if (! defined $error) {
            $error = "FileNotFoundException: Error looking up file $filename. Error was:\n\t$!";
        }
        die $error;
    }
    return $filename;
}

=head2 ensureIsDir

    my $dirname = $CLASS->ensureIsFile( $dirname, [$error] );

Returns $dirname if it is defined and -d works, otherwise dies with $error.
If $error is not defined, then dies with error message:

    "ValueNotDefinedException: Expected a defined value.\n";
    "FileNotFoundException: Error looking up file named $dirname. Error was:\n\t$!";

=cut

sub ensureIsDir {
    my $class = shift;
    my $dirname = shift;
    my $error = shift;
    if (! defined $dirname) {
        if (! defined $error) {
            $error = "ValueNotDefinedException: Expected a defined value.\n";
        }
        die $error;
    }
    if (! -d $dirname) {
        if (! defined $error) {
            $error = "DirNotFoundException: Error looking up directory $dirname. Error was:\n\t$!";
        }
        die $error;
    }
    return $dirname;
}

=head2 ensureIsObject

    my $object = ensureIsObject( $object, [$wantClass], [$error] );

Returns the specified object if it is an object, or throws an error. If
$wantClass is specified, then it is an error if $object is not of class
$wantClass. Inheritance is ignored.

If an error is thrown, either dies with $error, if specified, or dies with one
of the following messages:

 "ValueNotDefinedException: Expected a defined value.\n";
 "ValueNotObjectException: Not an object.\n";
 "ValueNotExpectedClass: Wanted object of class $wantClass, "
     . "was $objectClass.\n";
 
=cut

sub ensureIsObject {
    my $class = shift;
    my $object = shift;
    my $wantClass = shift;
    my $error = shift;

    if (! defined $object) {
        if (! defined $error) {
            $error = "ValueNotDefinedException: Expected a defined value.\n";
        }
        die $error;
    }
    my $objectClass = blessed $object;
    if (! defined $objectClass) {
        if (! defined $error) {
            $error = "ValueNotObjectException: Not an object.\n";
        }
        die $error;
    }
    if (defined $wantClass && $objectClass ne $wantClass) {
        if (! defined $error) {
            $error = "ValueNotExpectedClass: Wanted object of class $wantClass, was $objectClass.\n";
        }
        die $error;
    }
    return $object;
}

=head2 checkCompatibleHash

    my $badValuesHR = checkCompatibleHash( oneHR, twoHR );

Compares the two hashes to see if all common keys have the same values,
including undefined keys. Any with values not in common are returned
in a hash-ref pointing to an array with the values from the first and second
hashes, respectively. Putting the smaller hash first is the most efficient
thing to do.

=cut

sub checkCompatibleHash {
    my $class   = shift;
    my $oneHR   = shift;
    my $twoHR   = shift;

    if ( ! defined $oneHR ) {
        return;
    }
    if ( ! defined $twoHR ) {
        return;
    }

    my $bad;

    for my $key (keys %$oneHR) {
        if (exists $twoHR->{"$key"}) {
            my $oneVal = $oneHR->{"$key"};
            my $twoVal = $twoHR->{"$key"};
            if (! defined $oneVal) {
                if (! defined $twoVal) {
                    next;
                }
                else {
                    $bad->{"$key"} = [$oneVal, $twoVal];
                }
            }
            elsif (! defined $twoVal) {
                $bad->{"$key"} = [$oneVal, $twoVal];
            }
            elsif ( $oneVal ne $twoVal ) {
                $bad->{"$key"} = [$oneVal, $twoVal]; 
            }
        }
    }
    return $bad;
}

=head2 reformatTimestamp()

    my $newFormatTimestamp = $CLASS->reformatTimestamp( $timestamp );

Takes a postgresql formatted timestamp (without time zone) and converts it to
an aml time stamp by replacing the blank space between the date and time with
a capital "T". Expects the incoming $timestamp to be formtted as
C<qr/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}\d{2}\.?\d*$/>

=cut

sub reformatTimestamp() {
    my $class = shift;
    my $pgdbTimestampNoTimeZone = shift;
 
    if ($pgdbTimestampNoTimeZone !~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.?\d*$/ ) {
        croak( "BadParameterException: Incorectly formatted time stamp: $pgdbTimestampNoTimeZone\n"
             . ' expected 24 hour fromat like "YYYY-MM-DD HH:MM:SS.frac'
              . " with optional part. No other spaces allowed.\n"
        );
    }

    my $xmlFormatTimestamp = $pgdbTimestampNoTimeZone;
    $xmlFormatTimestamp =~ s/ /T/;

    return  $xmlFormatTimestamp;
}

=head2 getFileBaseName

   my ($base, $ext) = $CLASS->getFileBaseName( "$filePath" );

Given a $filePath, extracts the filename and returns the file base name $base
and extension $ext. Everything up to the first "."  is returned as the $base,
everything after as the $ext. $filePath may or may not include directories,
relative or absolute, but the last element is assumed to be a filename (unless
it ends with a directory marker, in which case it is treated the same as if
$filePath was ""). If there is nothing before/after the ".", an empty string
will be returned for the $base and/or $ext. If there is no ., $ext will be
undef. Directory markers are "/", ".", or ".." on Unix

=head3 Examples:

             $filePath       $base        $ext
    ------------------  ----------  ----------
       "base.ext"           "base"       "ext"
       "base.ext.more"      "base"  "ext.more"
            "baseOnly"  "baseOnly"       undef
           ".hidden"            ""    "hidden"
       "base."              "base"          ""
           "."                  ""          ""
                    ""          ""       undef
                 undef      (dies)            
    "path/to/base.ext"      "base"       "ext"
   "/path/to/base.ext"      "base"       "ext"
    "path/to/"              ""           undef
    "path/to/."             ""           undef
    "path/to/.."            ""           undef

=cut

sub getFileBaseName {

    my $class = shift;
    my $path = shift;

    if (! defined $path) {
        croak "BadParameterException: Undefined parmaeter, getFileBaseName().\n";
    }

    my ($vol, $dir, $file) = File::Spec->splitpath( $path );
    if ($file eq "") { return ("", undef); }
    $file =~ /^([^\.]*)(\.?)(.*)$/;
    my ($base, $ext);
    if ($2 eq '.') { ($base, $ext) = ("", ""); }
    if ($1)        { $base = $1; }
    if ($3)        { $ext  = $3; }
    return ($base, $ext);
}

=head1 INSTANCE METHODS

=cut

=head2 run()

    $obj->run()

Implements the actions taken when run as an application. Currently only
returns 1 if succeds, or prints error and returns 0 if something dies with
an error message.

=cut

sub run {
    my $self = shift;
    eval {
        $COMMAND_DISPATCH_HR->{$self->{'command'}}(($self));
    };
    if ($@) {
        my $error = $@;
        $self->sayError( $error );
        return 0;
    }
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

    $self->{'id'}        = $CLASS->getUuid();
    $self->{'dbh'}       = undef;

    # Template files are tightly coupled, so provided with distro. Might want
    # to have multiple versions, so are in subdirectory SRA_1-5.
    $self->{'xmlSchema'} = 'SRA_1-5',
    $self->{'templateBaseDir'}  = dist_dir('Bio-SeqWare-Uploads-CgHub-Bam'),

    # Might want to make these options and pass in by config file.
    $self->{'cghubSubmitExec'}  = '/usr/bin/cgsubmit',
    $self->{'cghubUploadExec'}  = '/usr/bin/gtupload',
    $self->{'cghubSubmitUrl'}   = 'https://cghub.ucsc.edu/',
    $self->{'chghubSubmitCert'} = '/datastore/alldata/tcga/CGHUB/Key.20140221/cghub.key',

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
    if ($self->{'dbh'} && $self->{'dbh'}->{'Active'}) {
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

        # Data options
        'workflow_id=i' => \$opt{'workflow_id'},

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
    for my $key (keys %opt) {
        if ( ! defined $opt{"$key"} ) {
            delete $opt{"$key"};
        }
    }
    return \%opt;
}

=head2 parseSampleFile 

    my $sampleDataRecords = $self->parseSampleFile()

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
            if ( length ( $fields[$col] ) < 1 ) {
                $lineHR->{"$headings[$col]"} = undef;
            }
            else {
                $lineHR->{"$headings[$col]"} = $fields[$col];
            }
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
    my $optHR = $configParser->getAll();
    return $optHR;
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

    my $val = $optHR->{'workflow_id'};
    unless ( $val ) { croak("--workflow_id option required." ); };
    my %okVals = ( '38' => 1, '39' => 1, '40' => 1);
    unless (exists $okVals{$val}) { croak("--workflow_id must be 38, 39, or 40." ); };
    $self->{'workflow_id'} = $val;

    return 1;
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

=head2 do_launch

Called automatically by runner framework to implement the launch command.
Not intended to be called directly. Implemets the "launch" step of the
workflow.

Uses parseSampleFile() to generate a list to upload. Each entry in this list is
processed and upload independently as follows:

1. _launch_prepareQueryInfo(): Adaptor mapping output hash from parseSampleFile
to input hash for dbGetBamFileInfo()

2. dbGetBamFileInfo() is a fairly generic query into the database given 
a minimal hash of lookup data. It outputs a hash with a bunch of database data.
Data in the lookup set beyond what is required for retrieval is validated
against the database data retrieved when the keys match.

3. _launch_prepareUploadInfo(): Adaptor mapping output hash from dbGetBamFileInfo
to input hash for dbinsertUpload.

4. dbinsertUpload() Inserts the upload record for the above data and returns
the upload_id inserted.

5. The upload_id is added to the data.

6. dbinsertUploadFile() inserts the upoad file record 

7. The upload record is marked as failed if an errors occured in 6 (Can't
record any errors earlier as the upload record does not yet exist. Otherwise
it is marked as done.

=cut

sub do_launch {
    my $self = shift;

    if (! defined $self->{'sampleFile'}) {
        croak "Currently must specify the sample file to process as launch argument.\n";
    }

    my $selectedDAT = $self->parseSampleFile();

    for my $selectedHR (@$selectedDAT) {
        my $queryHR = $self->_launch_prepareQueryInfo( $selectedHR );
        my $seqRunDAT = $self->dbGetBamFileInfo( $queryHR );
        my $uploadHR = $self->_launch_prepareUploadInfo($seqRunDAT);
        my $upload_id = $self->dbInsertUpload( $uploadHR );
        $uploadHR->{'upload_id'} = $upload_id;
        eval {
            $self->dbInsertUploadFile( $uploadHR );
        };
        if ($@) {
            my $error = $@;
            $self->dbSetFail( $uploadHR, "launch", $@ );
        }
        else {
            $self->dbSetDone( $uploadHR, "launch" );
        }
    }
    return 1;
}

=head2 do_meta_generate

Called automatically by runner framework to implement the meta-generate command.
Not intended to be called directly.

=cut

sub do_meta_generate {
    my $self = shift;

    my $uploadHR;
    eval {
        $uploadHR = $self->dbSetRunning( 'launch', 'meta-generate' );
        $self->sayDebug( 'Running meta_generate on: ', $uploadHR );
        if ($uploadHR)  {
            my $dataHR = $self->_metaGenerate_getData( $uploadHR );
            $dataHR->{'dataDir'} = $self->_metaGenerate_makeDataDir( $dataHR );
            $dataHR->{'linkName'} = $self->_metaGenerate_linkBam( $dataHR );
            my $analysisXml   = File::Spec->catfile($dataHR->{'dataDir'}, 'analysis.xml', 'analysis.xml.template' );
            my $runXml        = File::Spec->catfile($dataHR->{'dataDir'}, 'run.xml', 'run.xml.template' );
            my $experimentXml = File::Spec->catfile($dataHR->{'dataDir'}, 'experiment.xml', 'experiment.xml.template');
            $self->_metaGenerate_makeFileFromTemplate( $dataHR, $analysisXml   );
            $self->_metaGenerate_makeFileFromTemplate( $dataHR, $runXml        );
            $self->_metaGenerate_makeFileFromTemplate( $dataHR, $experimentXml );
            $self->dbSetDone( $uploadHR, 'meta-generate');
        }
    };
    if ($@) {
        my $error = $@;

        if ($uploadHR) {
            $error = $self->dbSetFail( $uploadHR, 'meta-generate', $error);
        }
        else {
            $error .= "\tAlso: upload data not available\n";
        }
        $self->dbDie($error);
    }
    return 1;
}

=head2 do_meta_validate

Called automatically by runner framework to implement the meta-validate command.
Not intended to be called directly.

=cut

sub do_meta_validate {
    my $self = shift;
    return 1;
}

=head2 do_meta_upload

Called automatically by runner framework to implement the meta-upload command.
Not intended to be called directly.

=cut

sub do_meta_upload {
    my $self = shift;
    return 1;
}

=head2 do_file_upload

Called automatically by runner framework to implement the file_upload command.
Not intended to be called directly.

=cut

sub do_file_upload {
    my $self = shift;
    return 1;
}

=head2 do_status_update

Called automatically by runner framework to implement the status-update command.
Not intended to be called directly.

=cut

sub do_status_update {
    my $self = shift;
    return 1;
}

=head2 do_status_remote

Called automatically by runner framework to implement the status-remote command.
Not intended to be called directly.

=cut

sub do_status_remote {
    my $self = shift;
    return 1;
}

=head2 do_status_local

Called automatically by runner framework to implement the status-local command.
Not intended to be called directly.

=cut

sub do_status_local {
    my $self = shift;
    return 1;
}

=head2 dbSetDone

    my $self->dbSetDone( $hashRef, $step );

Simple a wrapper for dbSetUploadStatus, returns the result of calling that with
the "upload_id" key from the provided $hashRef and a new status of
"$step" . "_done"

=cut

sub dbSetDone {
    my $self = shift;
    my $uploadHR = shift;
    my $step = shift;

    return $self->dbSetUploadStatus( $uploadHR->{'upload_id'}, $step . "_done" );
}

=head2 dbSetFail

    my $self->dbSetDone( $hashRef, $step, $error );

A wrapper for dbSetUploadStatus, Calls that with the "upload_id" key from the
provided $hashRef and a new status of
"$step" . "_fail_" . getErrorName( $error )

The $error will be return, but if an error occurs in trying to set fail, that
error will be *prepended* to $error before returning, separated with the string
"\tTried to fail run because of:\n"

=cut

sub dbSetFail {
    my $self = shift;
    my $uploadHR = shift;
    my $step = shift;
    my $error = shift;

    my $errorName = $CLASS->getErrorName($error);

    eval{
        $self->dbSetUploadStatus($uploadHR->{'upload_id'}, $step . "_failed_" . $errorName);
    };
    if ($@) {
        $error = $@ . "\tTried to fail run because of:\n$error";
    }
    return $error;
}

=head2 dbSetRunning

   my $uploadRec = dbSetRunning( $stepDone, $stepRunning )

Given the previous step and the next step, finds one record in the database
in state <$stepDone>_done, sets its status to <$stepRunning>_running, and
returns the equivqalent hash-ref. This is done in a transaction so it is safe
to run these steps overlapping each other.

=cut

sub dbSetRunning {
    my $self = shift;
    my $stepDone = shift;
    my $stepRunning = shift;


    $stepDone = $stepDone . "_done";
    $stepRunning = $stepRunning . "_running";
    my $dbh = $self->getDbh();

    my $selectRunSQL = "SELECT * FROM upload WHERE status = ?
        ORDER BY upload_id DESC LIMIT 1";

    my $selectRun = $dbh->prepare( $selectRunSQL );

    my $uploadRecHR;

    eval {
        # Transaction to ensures 'find' and 'tag as found' occur in one step,
        # allowing for parallel running.
        $dbh->begin_work();
        $dbh->do("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE");
        $selectRun->execute( $stepDone );
        my $rowHR = $selectRun->fetchrow_hashref();
        $selectRun->finish();
        if (! exists $rowHR->{'upload_id'}) {

            say('Nothing to do.');
        }
        else {
            $self->dbSetUploadStatus( $rowHR->{ 'upload_id' }, $stepRunning );
            $uploadRecHR = \%$rowHR;
            $uploadRecHR->{'status'} = $stepRunning;
        }
        $dbh->commit();
    };
    my $error = $@;
    if ($error) {
        $self->dbDie("DbSetRunningException: Failed to select lane to run because of:\n$error\n");
    }
    return $uploadRecHR;
}

=head2 dbSetUploadStatus

    my $self->dbSetUploadStatus( $upload_id, $newStatus )

Changes the status of the specified upload record to the specified status.
Either returns 1 for success or dies with error.

=cut

sub dbSetUploadStatus {
    my $self = shift;
    my $upload_id = shift;
    my $newStatus = shift;

    my $dbh = $self->getDbh();
    my $updateUploadRecSQL =
        "UPDATE upload SET status = ? WHERE upload_id = ?";
    eval {
        my $updateSTH = $dbh->prepare($updateUploadRecSQL);
        my $isOk = $updateSTH->execute( $newStatus, $upload_id );
        my $updateCount = $updateSTH->rows();
        $updateSTH->finish();
        if ($updateCount != 1) {
            #Not db die, that is caught on outer loop.
            die( "Updated " . $updateCount . " update records, expected 1.\n");
        }
    };
    if ($@) {
        $self->dbDie( "DbStatusUpdateException: Failed to change upload record $upload_id to $newStatus.\nCleanup likely needed. Error was:\n$@\n");
    }

    return 1;

}

=head2 _launch_prepareQueryInfo

    my $queryHR = $self->_launch_translateToQueryInfo( $parsedUploadList );

Data processing step converting a hash obtained from parseSampleFile
to that useable by dbGetBamFileInfo. Used to isolate the code mapping the
headers from the file to columns in the database and to convert file value
representations to those used by the database. This is ill defined and a
potential change point.

=cut

sub _launch_prepareQueryInfo {
    my $self = shift;
    my $inHR = shift;

    my %queryInfo = %$inHR;
    $queryInfo{'lane_index' } = $inHR->{'lane'} - 1;
    $queryInfo{'workflow_id'} = $self->{'workflow_id'};
    if (exists $inHR->{'bam_file'}) {$queryInfo{'file_path'} = $inHR->{'bam_file'};};
    if (exists $inHR->{'file_path'}) {$queryInfo{'file_path'} = $inHR->{'file_path'};};

    return \%queryInfo
}

=head2 _launch_prepareUploadInfo

    my $uploadsAR = $self->_launch_prepareUploadInfo( $queryHR );

Data processing step converting a hash obtained from dbGetBamFileInfo
to that useable by dbInsertUpload(). Used to isolate the code mapping the
data recieved from the generic lookup routine to the specific upload
information needed by this program in managing uploads of bam files to cghub.
This is a potential change point.

=cut

sub _launch_prepareUploadInfo {
    my $self = shift;
    my $datHR = shift;

   my %upload = (
      'sample_id'         => $datHR->{'sample_id'},
      'file_id'           => $datHR->{'file_id'},
      'target'            => 'CGHUB_BAM',
      'status'            => 'launch_running',
      'metadata_dir'      => '/datastore/tcga/cghub/v2_uploads',
      'cghub_analysis_id' => $CLASS->getUuid(),
   );

   return \%upload;
}

=head2 _makeFileFromTemplate

  $obj->_makeFileFromTemplate( $dataHR, $outFile );
  $obj->_makeFileFromTemplate( $dataHR, $outFile, $templateFile );

Takes the $dataHR of template values and uses it to fill in the
a template ($templateFile) and generate an output file ($outFile). Returns
the path to the created $outFile file, or dies with error.
When $templateFile are relative, default directories are
used from the object.

USES

    'templateBaseDir' = Absolute basedir to use if $templateFile is relative.
    'xmlSchema'       = Schema version, used as subdir under templateBaseDir
                        if $templateFile is relative.

=cut

sub _metaGenerate_makeFileFromTemplate {

    my $self   = shift;
    my $dataHR = shift;
    my $outFile = shift;
    my $templateFile = shift;

    $CLASS->ensureIsDefined($dataHR);
    $CLASS->ensureIsDefined($outFile);

    my $templateAbsFilePath = $templateFile;
    if (! File::Spec->file_name_is_absolute( $templateFile )) {
        $templateAbsFilePath = File::Spec->catfile(
            $self->{'templateBaseDir' },
            $self->{'xmlSchema' },
            $templateFile
        );
        $self->sayVerbose( "Using default template file path: $templateAbsFilePath\n" );
    }
    $CLASS->ensureIsFile($templateAbsFilePath);

    $self->sayDebug( "TEMPLATE: $templateAbsFilePath\n"
            ."OUTFILE: $outFile\n"
            ."DATA: \n",
            $dataHR
    );

    # Stamp output file from merged dataHR and template file
    eval {
        my $templateManager = Template->new({ 'ABSOLUTE' => 1, });
        my $ok = $templateManager->process( $templateAbsFilePath, $dataHR, $outFile  );
        if (! $ok) {
            die( $templateManager->error() . "\n");
        }
        $CLASS->ensureIsFile(
            $outFile,
            "Can't find the file I should have just created: $outFile\n"
        );
    };
    if ($@) {
        my $error = $@;
        die ( "FileFromTemplateException: Failed creating file \"$outFile\" from template \"$templateAbsFilePath\". Error was:\n\t$error");
    }

    return $outFile;
}

=head2 _metaGenerate_getDataPreservation

 my $preservation = $self->_metaGenerate_getDataPreservation( 'preservation );

If preservation contains "FFPE" (case insensitively), return 'FFPE' else
default to 'FROZEN';

=cut

sub _metaGenerate_getDataPreservation {
    my $self = shift;
    my $preservation = shift;

    if (! defined $preservation ) {
        $preservation = 'FROZEN';
    }
    elsif ($preservation =~ /FFPE/i) {
        $preservation = "FFPE";
    }
    else {
        $preservation = 'FROZEN';
    }

    return $preservation;

}

=head2 _metaGenerate_getDataLibraryPrep

    my $libraryPrep = $self->_metaGenerate_getDataLibraryPrep( $library_prep );

The library prep is either something containing the string TotalRNA, case
insensitively, in which case it is returned as is, or it is set to
Illumina TruSeq.

=cut

sub _metaGenerate_getDataLibraryPrep {
    my $self = shift;
    my $libraryPrep = shift;

    if (! defined $libraryPrep) {
        $libraryPrep = "Illumina TruSeq";
    }
    elsif ($libraryPrep !~ /TotalRNA/i) {
        $libraryPrep = "Illumina TruSeq";
    }

    return $libraryPrep;
}

=head2 _metaGenerate_getData

    $self->_metaGenerate_getData()

=cut

sub _metaGenerate_getData {
    my $self = shift;
    my $uploadHR = shift;

    $CLASS->ensureHashHasValue($uploadHR, 'upload_id', "GetData needed hash with upload_id defined.");
    my $upload_id = $uploadHR->{'upload_id'};

    my $dbh = $self->getDbh();

    my $selectAllSQL =
       "SELECT vf.tstmp             as file_timestamp,
               vf.workflow_accession,
               vf.file_sw_accession as file_accession,
               vf.md5sum            as file_md5sum,
               vf.file_path,
               vf.workflow          as workflow_name,
               vf.workflow_version,
               vf.algorithm         as workflow_algorithm,
               p.instrument_model,
               l.sw_accession       as lane_accession,
               e.sw_accession       as experiment_accession,
               e.name               as library_prep,
               e.description        as experiment_description,
               e.experiment_id,
               s.sw_accession       as sample_accession,
               s.tcga_uuid,
               s.preservation
        FROM upload u, upload_file uf, vw_files vf, lane l, experiment e, sample s, platform p
        WHERE u.upload_id = ?
          AND u.upload_id = uf.upload_id
          AND uf.file_id = vf.file_id
          AND vf.lane_id = l.lane_id
          AND s.sample_id = u.sample_id
          AND e.experiment_id = s.experiment_id
          AND e.platform_id = p.platform_id";


    my $dataHR;
    eval {
        my $selectionSTH = $dbh->prepare( $selectAllSQL );
        $selectionSTH->execute( $upload_id );
        my $rowHR = $selectionSTH->fetchrow_hashref();
        my $badHR = $selectionSTH->fetchrow_hashref();
        if ($badHR) {
            my $error = "Dulicate data record 1:\n\t" . Dumper($rowHR)
            . "\nDulicate data record 2:\n\t" . Dumper($badHR);
            die "DbDuplicateRecordException: Data record retrieved should be unique:\n\t$error";
        }
        $selectionSTH->finish();

        # run.xml

        my $runDataHR = {
            'lane_accession'       => $rowHR->{'lane_accession'},
            'experiment_accession' => $rowHR->{'experiment_accession'},
            'sample_accession'     => $rowHR->{'sample_accession'},
        };

        # analysis.xml

        my $uploadIdAlias =
            "upload_" . $upload_id;

        my $analysisDate =
            $CLASS->reformatTimestamp( $rowHR->{'file_timestamp'} );

        my $readGroup =
            $self->_metaGenerate_getDataReadGroup( $rowHR->{'file_path'} );

        my $fileNoExtension =
            ($CLASS->getFileBaseName( $rowHR->{'file_path'} ))[0];

        my $fileName =
            (File::Spec->splitpath( $rowHR->{'file_path'} ))[2];

        my $localFileLink =
            "UNCID_"
            . $rowHR->{'file_accession'} . '.'
            . $rowHR->{'tcga_uuid'} . '.'
            . $fileName;

        my $analysisDataHR = {
            'uploadIdAlias'      => $uploadIdAlias,
            'analysisDate'       => $analysisDate,
            'workflow_accession' => $rowHR->{'workflow_accession'},
            'tcga_uuid'          => $rowHR->{'tcga_uuid'},
            'lane_accession'     => $rowHR->{'lane_accession'},
            'readGroup'          => $readGroup,
            'fileNoExtension'    => $fileNoExtension,
            'workflow_name'      => $rowHR->{'workflow_name'},
            'workflow_version'   => $rowHR->{'workflow_version'},
            'workflow_algorithm' => $rowHR->{'workflow_algorithm'},
            'file_accession'     => $rowHR->{'file_accession'},
            'file_md5sum'        => $rowHR->{'file_md5sum'},
            'uncFileSampleName'  => $localFileLink,
            'file_path'          => $rowHR->{'file_path'},
        };

        # experiment.xml

        my $libraryPrep =
            $self->_metaGenerate_getDataLibraryPrep($rowHR->{'library_prep'});

        my $readEnds =
            $self->_metaGenerate_getDataReadCount( $rowHR->{'experiment_id'} );
        if ($readEnds != 2) {
            die "BadReadEnds: Only paired end (2 reads) allowed, not $readEnds.\n";
        }

        my $baseCoord =
            $self->_metaGenerate_getDataReadLength( $rowHR->{'file_path'} );

        my $preservation =
            $self->_metaGenerate_getDataPreservation( $rowHR->{'preservation'} );

        my $experimentDataHR = {
            'experiment_accession'   => $rowHR->{'experiment_accession'},
            'sample_accession'       => $rowHR->{'sample_accession'},
            'experiment_description' => $rowHR->{'experiment_description'},
            'tcga_uuid'              => $rowHR->{'tcga_uuid'},
            'libraryPrep'            => $libraryPrep,
            'LibraryLayout'          => "PAIRED",
            'readEnds'               => $readEnds,
            'baseCoord'              => $baseCoord,
            'instrument_model'       => $rowHR->{'instrument_model'},
            'preservation'           => $preservation,
        };


        # Merge data.

        # Hard to test these, indicates this is probably multiple subroutines
        # TODO: split.

        my $bad = $CLASS->checkCompatibleHash($runDataHR, $experimentDataHR);
        # uncoverable branch true
        if ($bad) {
            # uncoverable statement
            die "BadDataException: run and experiment data different. Error was:\n\t" . Dumper($bad) . "\n";
        }
        $bad = $CLASS->checkCompatibleHash($runDataHR, $analysisDataHR);
        # uncoverable branch true
        if ($bad) {
            # uncoverable statement
            die "BadDataException: run and analysis data different. Error was:\n\t" . Dumper($bad) . "\n";
        }
        $bad = $CLASS->checkCompatibleHash($analysisDataHR, $experimentDataHR);
        # uncoverable branch true
        if ($bad) {
            # uncoverable statement
            die "BadDataException: analysis and experiment data different. Error was:\n\t" . Dumper($bad) . "\n";
        }

        my %data = (%$analysisDataHR, %$experimentDataHR, %$runDataHR);
        $dataHR = \%data;

        $bad = $CLASS->checkCompatibleHash($dataHR, $uploadHR);
        if ($bad) {
            die "BadDataException: template data and upload data different. Mismatch was:\n\t" . Dumper($bad) . "\n";
        }

        %data = (%$dataHR, %$uploadHR);
        $dataHR = \%data;

        # Validate
        $self->sayDebug( "Template data is: ", $dataHR );

        for my $key (sort keys %$dataHR) {
            next if $key eq 'external_status';  # Should be null at this point.
            $CLASS->ensureHashHasValue($dataHR, $key, "Problem with data, key \'$key\'");
        }
    };
    if ($@) {
        my $error = $@;
        $self->dbDie("MetaDataGenerateException: Failed collecting data for template use. Error was:\n\t$error");
    }

    return $dataHR;
}

=head2 _metaGenerate_getDataReadCount

    $ends = $self->_metaGenerate_getDataReadCount( $eperiment.sw_accession );

Returns 1 if single ended, 2 if paired-ended. Based on the number
of application reads in the associated experiment_spot_design_read_spec.
Dies if any other number found, or if any problem with db access.

=cut

sub _metaGenerate_getDataReadCount {

    my $self         = shift;
    my $experimentId = shift;

    my $dbh = $self->getDbh();

    my $readCountSQL = 
        "SELECT count(*) as read_ends
         FROM experiment_spot_design_read_spec AS rs,
                        experiment_spot_design AS d,
                                    experiment AS e
         WHERE  e.experiment_id                 = ?
           AND  e.experiment_spot_design_id     = d.experiment_spot_design_id
           AND rs.experiment_spot_design_id     = d.experiment_spot_design_id
           AND rs.read_class                    =  'Application Read'
           AND rs.read_type                    !=  'BarCode'";

    my $readEnds;
    eval {
        my $readCoundSTH = $dbh->prepare( $readCountSQL );
        $readCoundSTH->execute( $experimentId );
        my $rowHR = $readCoundSTH->fetchrow_hashref();
        $readCoundSTH->finish();
        $readEnds = $rowHR->{'read_ends'};
        if (! defined $readEnds) {
             die "DbLookupError: Nothing retrieved from database.\n";
        }
        unless ($readEnds == 1 || $readEnds == 2) {
             die "DbDataError: Found $readEnds read ends, expected 1 or 2.\n";
        }
    };
    if ($@) {
        my $error = $@;
        $self->dbDie( "DbReadCountException: Failed to retrieve the number of reads. Error was:\n\t$@" );
    }

    return $readEnds;
}

=head2 _metaGenerate_getDataReadGroup

    my $readGroup = $self->_metaGenerate_getDataReadGroup( $bamFile );

Gets the read group from the bam file using samtools and some unix tools.

=cut

sub _metaGenerate_getDataReadGroup {
    my $self = shift;
    my $bamFile = shift;

    my $read_group;
    my $SAMTOOLS_EXEC = '/datastore/tier1data/nextgenseq/seqware-analysis/software/samtools/samtools';
    eval {
        $CLASS->ensureIsFile( $bamFile );


        my $command = "$SAMTOOLS_EXEC view -H $bamFile";
        $self->sayVerbose( "READ LENGTH COMMAND: \"$command\"" );
        my $bamHeaderString = qx/$command/;
        if ($?) {
            die ("SamtoolsFailedException: Error getting read group. Exit error code: $?. Failure message was:\n$!"
                . "\n\tOriginal command was:\n$command\n" );
        }
        if (! $bamHeaderString) {
            $self->{'error'} = "";
            die( "SamtoolsExecNoOutputException: Neither error nor result generated. Strange.\n"
                . "\n\tOriginal command was:\n$command\n" );
        }
        my @bamHeaders = split( "\n", $bamHeaderString );
        my @readGroupLines = grep( /^\@RG/, @bamHeaders );
        my  $readGroupCount = scalar @readGroupLines;
        if ($readGroupCount != 1) {
            die "ReadGroupNumberException: One and only one readgroup allowed. Found $readGroupCount lines:n\t" . Dumper(\@readGroupLines);
        }
        $readGroupLines[0] =~ /\tID:([^\t]+).*$/;
        $read_group = $CLASS->ensureIsDefined($1);
 
    };
    if ($@) {
        my $error = $@;
        die ( "ReadGroupException: Can't determine read group because:\n\t$error" );
    }
    return $read_group;

}

=head2 _metaGenerate_getDataReadLength

   $baseCountPerRead = _metaGenerate_getDataReadLength( $bam_file_path );

Examines first 1000 lines of the bam file and returns the length of the
longest read found.

=cut

sub _metaGenerate_getDataReadLength {

    my $self = shift;
    my $bamFile = shift;

    my $SAMTOOLS_EXEC = '/datastore/tier1data/nextgenseq/seqware-analysis/software/samtools/samtools';
    my $MIN_READ_LENGTH = 17;
    my $readLength = 0;

    eval {
        $CLASS->ensureIsFile( $bamFile );

        my $command = "$SAMTOOLS_EXEC view $bamFile | head -1000 | cut -f 10";
        $self->sayVerbose( "READ LENGTH COMMAND: \"$command\"" );
        my $readStr = qx/$command/;

        if ($?) {
            die ("SamtoolsFailedException: Error getting reads. Exit error code: $?. Failure message was:\n$!"
                . "\n\tOriginal command was:\n$command\n" );
        }
        if (! $readStr) {
            $self->{'error'} = "";
            die( "SamtoolsExecNoOutputException: Neither error nor result generated. Strange.\n"
                . "\n\tOriginal command was:\n$command\n" );
        }
        my @reads = split (/\n/, $readStr);
        foreach my $read (@reads) {
            my $length = length($read);
            if ($length > $readLength) {
                $readLength = $length;
            }
        }

        if ( $readLength < $MIN_READ_LENGTH ) {
            $self->{'error'} = "low-read-length";
            die( "SamtoolsShortReadException: Max read length to short, was: $readLength.\n" );
        }
    };
    if ($@) {
        my $error = $@;
        die ( "ReadLengthException: Can't determine bam max read length because:\n\t$error" );
    }

    return $readLength;
}

=head2 _metaGenerate_makeDataDir

    my $dataDir = $self->_metaGenerate_makeDataDir( $dataHR );

Creates the target data directory which should just be
catdir ($dataHR->{'metadata_dir'}, $dataHR->{'cghub_analysis_id'});
The pre-existance of $dataHR->{'metadata_dir'} is
checked. If succeeds, returns the name of the new dataDir, else dies
with error.

=cut

sub _metaGenerate_makeDataDir {
    my $self = shift;
    my $dataHR = shift;

    my $baseDir     = $CLASS->ensureHashHasValue( $dataHR, 'metadata_dir', "Making data dir requires metadata_dir key");
    my $analysisId  = $CLASS->ensureHashHasValue( $dataHR, 'cghub_analysis_id', "Making data dir requires metadata_dir key");
    $CLASS->ensureIsDir( $baseDir );

    my $wantDir = File::Spec->catdir( $baseDir, $analysisId );

    eval {
        mkpath($wantDir, { mode => 0775 });
    };

    if ($@) {
        my $error = $@;
        die "CreateDirectoryException: Unable to create path \"$wantDir\". Error was:\n\t$error";
    }
    return $wantDir;
}

=head2 _metaGenerate_linkBam

    my $bamLink = $self->_metaGenerate_linkBam( $dataHR );

Creates a link to $dataHR->{'file_path'} in the $dataHR->{'dataDir'}.
The file_path and the dataDir must exist. The link is named after the
<filename> extracted from the file_path, The <file_accession>, and the
<sample_tcga_uuid> as

  UNCID_<file_accession>.<sample_tcga_uuid>.<filename.

The link name only (no path) will be returned.

=cut

sub _metaGenerate_linkBam {
    my $self = shift;
    my $dataHR = shift;

    my $targetFile       = $CLASS->ensureHashHasValue($dataHR, 'file_path'       );
    my $linkDir          = $CLASS->ensureHashHasValue($dataHR, 'dataDir'         );
    my $file_accession   = $CLASS->ensureHashHasValue($dataHR, 'file_accession'  );
    my $tcga_uuid = $CLASS->ensureHashHasValue($dataHR, 'tcga_uuid');
    $CLASS->ensureIsFile( $targetFile );
    $CLASS->ensureIsDir(  $linkDir    );

    my $fileName = (File::Spec->splitpath( $dataHR->{'file_path'} ))[2];
    my $linkName =
        "UNCID_" . $file_accession . '.' . $tcga_uuid . '.' . $fileName;
    my $link_path = File::Spec->catfile( $linkDir, $linkName );
    eval {
        symlink( $targetFile, $link_path);
    };
    if ($@) {
        my $error = $@;
        die "CreateLinkException: Could not create symlink:\n"
        . "\tLink: \"$link_path\"\n"
        . "\tPointing to: \"$targetFile\". Error was:\t\n$error\n";
    }
    return $linkName;
}

=head2 dbInsertUpload

    my $upload_id = $self->dbInsertUpload( $recordHR );

Inserts a new upload record. The associated upload_file record will be added
by dbInsertUploadFile. Either succeeds or dies with error. All data for
upload must be in the provided hash, with the keys the field names from the
upload table.

Returns the id of the upload record inserted.

=cut

sub dbInsertUpload {
    my $self = shift;
    my $rec = shift;
    my $dbh = $self->getDbh();

    my $insertUploadRecSQL =
        "INSERT INTO upload ( sample_id, target, status, cghub_analysis_id, metadata_dir)
         VALUES ( ?, ?, ?, ?, ? )
         RETURNING upload_id";

    my $upload_id;
    eval {
        my $insertSTH = $dbh->prepare($insertUploadRecSQL);
        my $isOk = $insertSTH->execute(
            $rec->{'sample_id'},
            $rec->{'target'},
            $rec->{'status'},
            $rec->{'cghub_analysis_id'},
            $rec->{'metadata_dir'},
        );
        my $rowHR = $insertSTH->fetchrow_hashref();
        $insertSTH->finish();
        if (! $rowHR->{'upload_id'}) {
            $self->dbDie( "Id of the upload record inserted was not retrieved.\n" );
        }
        $upload_id = $rowHR->{'upload_id'};
    };
    if ($@) {
         my $error = $@;
         $self->dbDie("dbUploadInsertException: Insert of new upload record failed. Error was:\n$error\n");
    }

    return $upload_id;
}

=head2 dbDie

   $self->dbDie( $errorMessage );

Call to die due to a database error. Wraps a call to die with code to clean up
the database connection, rolling back any open transaction and closing and 
destroying the current database connection object.

It will check if a transaction was not finished and do a rollback, If that
was tried and failed, the error message will be appended with:
"Also:\n\tRollback failed because of:\n$rollbackError", where $rollbackError
is the error caught during the attmptedrollback.

All errors during disconnect are ignored.

If the error thrown by dbDie is caught and handled, a new call to getDbh
will be needed as the old connection is no more.

=cut

sub dbDie {

    my $self = shift;
    my $error = shift;

    $CLASS->ensureIsObject( $self, $CLASS );

    if ($self->{'dbh'}) {
        if ($self->{'dbh'}->{'Active'}) {
             unless ($self->{'dbh'}->{'AutoCommit'}) {
                 eval {
                     $self->{'dbh'}->rollback();
                     if ($self->{'verbose'}) {
                         $error .= "\n\tRollback was performed.\n";
                     }
                 };
                 if ($@) {
                     $error .= "\n\tAlso: DbRollbackException: Rollback failed because of:\n$@";
                 }
             }
        }
        eval { $self->{'dbh'}->disconnect(); };
        # Ignore disconnect errors!
        $self->{'dbh'} = undef;
    }
    die $error;
}

=head2 dbInsertUploadFile

    my $upload_id = $self->dbInsertUploadFile( $recordHR );

Inserts a new uploadFile record. The associated upload record must already
exist (i.e. have been inserted by dbInsertUpload). Either succeeds or
dies with error. All data for upload-file must be in the provided hash, with
the keys the field names from the uploadFile table.

Returns the id of the file record linked to.

=cut

sub dbInsertUploadFile {
    my $self = shift;
    my $rec = shift;
    my $dbh = $self->getDbh();

    my $insertUploadFileRecSQL =
        "INSERT INTO upload_file ( upload_id, file_id)
         VALUES ( ?, ? )
         RETURNING file_id";

    my $file_id;
    eval {
        my $insertSTH = $dbh->prepare($insertUploadFileRecSQL);
        my $isOk = $insertSTH->execute(
            $rec->{'upload_id'},
            $rec->{'file_id'},
        );
        my $rowHR = $insertSTH->fetchrow_hashref();
        $insertSTH->finish();
        if (! $rowHR->{'file_id'}) {
            $self->dbDie( "Id of the file record linked to was not retrieved.\n");
        }
        $file_id = $rowHR->{'file_id'};
    };
    if ($@) {
         $self->dbDie( "DbUploadFileInsertException: Insert of new upload_file record failed. Error was:\n$@\n");
    }

    return $file_id;
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

=head2 dbGetBamFileInfo {

    $retrievedHR = $self->dbGetBamFileInfo( $lookupHR )

Looks up the bam file described by $lookupHR and returns a hash-ref of
information about it. Not very sophisticated. It requires the $lookupHR
t contain "sample", "flowcell", "lane_index", "barcode", and "workflow_id"
keys. If other keys are present, it will validate that retrieved
field with the same name have the same value; any differences is a fatal error.

Note that "barcode" should be undefined if looking up a non-barcoded lane, but
the key must be provided, and that lane_index is used (0 based) not lane.

=cut

sub dbGetBamFileInfo {
    my $self = shift;
    my $recHR = shift;
    my $dbh = $self->getDbh();

    my $sample      = $CLASS->ensureIsntEmptyString( $recHR->{'sample'     }, "BadDataException: Missing sample name."   );
    my $flowcell    = $CLASS->ensureIsntEmptyString( $recHR->{'flowcell'   }, "BadDataException: Missing flowcell name." );
    my $lane_index  = $CLASS->ensureIsntEmptyString( $recHR->{'lane_index' }, "BadDataException: Missing lane_index."    );
    my $workflow_id = $CLASS->ensureIsntEmptyString( $recHR->{'workflow_id'}, "BadDataException: Missing workflow_id."   );
    my $meta_type   = 'application/bam';
    my $type        = 'Mapsplice-sort';

    # Barcode may be NULL, signaled by false value in $recHR->{'barcode'}
    my $barcode;
    if (! exists $recHR->{'barcode'}) {
        die "BadDataException: Unspecified barcode.";
    }
    if (defined ($recHR->{'barcode'}) && $recHR->{'barcode'} eq '') {
        die "BadDataException: Barcode must be undef, not empty sting.";
    }
    $barcode = $recHR->{'barcode'};

    # Either select with barcode = ? or barcode is NULL
    my $bamSelectSQL = "SELECT * FROM vw_files WHERE meta_type = ? AND type = ?
        AND sample = ? AND flowcell = ? AND lane_index = ?
        AND workflow_id = ?";
    $bamSelectSQL .= $barcode ? " AND barcode = ?" : " AND barcode IS NULL";

    # Either need 7 params, or 8 if barcode is NULL
    my @bamSelectWhereParams = ( $meta_type, $type,
        $sample, $flowcell, $lane_index, $workflow_id );
    if ($barcode) {
        push @bamSelectWhereParams, $barcode;
    }

    my $bamSelectSTH = $dbh->prepare( $bamSelectSQL );
    $bamSelectSTH->execute( @bamSelectWhereParams );
    my $rowHR = $bamSelectSTH->fetchrow_hashref();
    my $twoFound = $bamSelectSTH->fetchrow_hashref();
    $bamSelectSTH->finish();
    if ($twoFound) {
        $self->dbDie( "DbDuplicateException: More than one record returned\n"
        . "Query: \"$bamSelectSQL\"\n"
        . "Parameters: " . Dumper(\@bamSelectWhereParams) . "\n");
    }

    my $badKeys = $CLASS->checkCompatibleHash( $recHR, $rowHR);
    if ($badKeys) {
        $self->dbDie( "DbMismatchException: Queried (1) and returned (2) hashes differ unexpectedly:\n"
        . Dumper($badKeys) . "\n"
        . "Query: \"$bamSelectSQL\"\n"
        . "Parameters: " . Dumper(\@bamSelectWhereParams) . "\n");
    }

    return $rowHR
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
    my $level = shift;
    my $host = hostname();
    my $timestamp = $CLASS->getTimestamp();
    my $id = $self->{'id'};
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
    my $level = shift;
    my $message = shift;

    chomp $message;
    my @lines = split( "\n", $message, 0);
    my $prefix = $self->getLogPrefix( $level ). " " ;
    my $newMessage;
    for my $line (@lines) {
        $newMessage .= $prefix . $line . "\n";
    }
    return $newMessage;
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
    elsif (blessed($object)) {
        $message .= "\n" . blessed($object) . " - " . $object;
    }
    elsif (defined $object) {
        $message = $message . "\n" . $object;
    }

    if ( $self->{'log'} ) {
        $message = $self->logifyMessage('DEBUG', $message);
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
    elsif (blessed($object)) {
        $message .= "\n" . blessed($object) . " - " . $object;
    }
    elsif (defined $object) {
        $message = $message . "\n"  . $object;
    }

    if ( $self->{'log'} ) {
        $message = $self->logifyMessage('VERBOSE', $message);
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
    elsif (blessed($object)) {
        $message .= "\n" . blessed($object) . " - " . $object;
    }
    elsif (defined $object) {
        $message = $message . "\n"  . $object;
    }

    if ( $self->{'log'} ) {
        $message = $self->logifyMessage('INFO', $message);
    }
    print $message;
}

=head2 sayError

   $self->sayError("Error message to print");
   $self->sayError("Something", $object);

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

sub sayError {
    my $self = shift;
    my $message = shift;
    my $object = shift;
    if (ref $object eq 'HASH' or ref $object eq 'ARRAY') {
        $message = $message . "\n" . Dumper($object);
    }
    elsif (blessed($object)) {
        $message .= "\n" . blessed($object) . " - " . $object;
    }
    elsif (defined $object) {
        $message = $message . "\n" . $object;
    }

    if ( $self->{'log'} ) {
        $message = $self->logifyMessage('ERROR', $message);
        print $message;
        return 1;
    }
    else {
        die $message;
    }
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
   $ cpanm https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam/archive/v0.000.003.tar.gz

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
