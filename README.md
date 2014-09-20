# NAME

Bio::SeqWare::Uploads::CgHub::Bam - Upload a bam file to CgHub

# VERSION

Version 0.000.005

# SYNOPSIS

    use Bio::SeqWare::Uploads::CgHub::Bam;

    my $obj = Bio::SeqWare::Uploads::CgHub::Bam->new();

# CLASS METHODS

## new()

    my $obj = Bio::SeqWare::Uploads::CgHub::Bam->new();

Creates and returns a Bio::SeqWare::Uploads::CgHub::Bam object. Either returns
an object of class Bio::Seqware::Uploads::CgHub::Bam or dies with an error
message. Will initialize and validate options.

## getTimestamp()

    Bio::SeqWare::Uploads::CgHub::Bam->getTimestamp().
    Bio::SeqWare::Uploads::CgHub::Bam->getTimestamp( $unixTime ).

Returns a timestamp formated like YYYY-MM-DD\_HH:MM:SS, zero padded, 24 hour
time. If a parameter is passed, it is assumed to be a unix epoch time (integer
or float seconds since Unix 0). If no parameter is passed, the current time will
be queried. Time is parsed through perl's localtime().

## getUuid

    my $uuid = $self->getUuid();

Creates and returns a new unique string form uuid like
"A3865E1F-9267-4267-BE65-AAC7C26DE4EF".

## getErrorName

    my $errorName = $CLASS->getErrorName( "SomeException: An error occured" );

Extract the error or exception name from the first word in a string, assuming
that word ends in exception or error (any case). The name is the preceeding
part, i.e. "Some" for the string above. If no string can be determined (i.e.)
the first word is not "\*exception" or "\*error", then the name will be Unknown.

## ensureIsDefined

    my $val = $CLASS->ensureDefined( $val, [$error] );

Returns $val if it is defined, otherwise dies with $error. If $error is not
defined, then dies with error message:

    "ValidationErrorNotDefined: Expected a defined value.\n";

## ensureHashHasValue

    my $val = $CLASS->ensureHashHasValue( $hashRef, $key, [$error] );

Returns $hashRef->{"$key"} if it is defined, otherwise dies with $error.
If $error is not defined, then dies with an appropriate message, one of:

    "ValidationErrorNotDefined: Expected a defined hash/hash-ref.\n";
    "ValidationErrorNotExists: Expected key $key to exist.\n";
    "ValidationErrorNotDefined: Expected a defined hash/hash-ref value for key $key.\n";

## ensureIsntEmptyString

    my $val = $CLASS->ensureIsntEmptyString( $val, [$error] );

Returns $val if, stringified, it is not an empty string. Otherwise dies with
$error. If $error is not defined, then dies with error message:

    "ValidationErrorBadString: Expected a non-empty string.\n";

## ensureIsFile

    my $filename = $CLASS->ensureIsFile( $filename, [$error] );

Returns $filename if it is defined and -f works, otherwise dies with $error.
If $error is not defined, then dies with error message:

    "ValueNotDefinedException: Expected a defined value.\n";
    "FileNotFoundException: Error looking up file named $filename. Error was:\n\t$!";

## ensureIsDir

    my $dirname = $CLASS->ensureIsFile( $dirname, [$error] );

Returns $dirname if it is defined and -d works, otherwise dies with $error.
If $error is not defined, then dies with error message:

    "ValueNotDefinedException: Expected a defined value.\n";
    "FileNotFoundException: Error looking up file named $dirname. Error was:\n\t$!";

## ensureIsObject

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
    

## checkCompatibleHash

    my $badValuesHR = checkCompatibleHash( oneHR, twoHR );

Compares the two hashes to see if all common keys have the same values,
including undefined keys. Any with values not in common are returned
in a hash-ref pointing to an array with the values from the first and second
hashes, respectively. Putting the smaller hash first is the most efficient
thing to do.

## reformatTimestamp()

    my $newFormatTimestamp = $CLASS->reformatTimestamp( $timestamp );

Takes a postgresql formatted timestamp (without time zone) and converts it to
an aml time stamp by replacing the blank space between the date and time with
a capital "T". Expects the incoming $timestamp to be formtted as
`qr/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}\d{2}\.?\d*$/`

## getFileBaseName

    my ($base, $ext) = $CLASS->getFileBaseName( "$filePath" );

Given a $filePath, extracts the filename and returns the file base name $base
and extension $ext. Everything up to the first "."  is returned as the $base,
everything after as the $ext. $filePath may or may not include directories,
relative or absolute, but the last element is assumed to be a filename (unless
it ends with a directory marker, in which case it is treated the same as if
$filePath was ""). If there is nothing before/after the ".", an empty string
will be returned for the $base and/or $ext. If there is no ., $ext will be
undef. Directory markers are "/", ".", or ".." on Unix

### Examples:

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

# INSTANCE METHODS

## run()

    $obj->run()

Implements the actions taken when run as an application. Currently only
returns 1 if succeds, or prints error and returns 0 if something dies with
an error message.

# INTERNAL METHODS

## init()

    my $self->init();

Sets up internal object data by loading cli options (including the config
filename) then loading the config file options and laying the cli options
over them. The combined options (hashref) is then passed to loadOptions which
does the validation and sets the final state of the internal object data.

Returns the fully initialized application object ready for running.

## DESTROY()

Called automatically upon destruction of this object. Should close the
database handle if opened by this class. Only really matters for error
exits. Planned exists do this manually.

## parseCli

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

- "\_argvAR"

    The original command line options and arguments, as an array ref.

- "\_argumentsAR"

    The arguments left after parsing options out of the command line, as an array ref.

## parseSampleFile 

    my $sampleDataRecords = $self->parseSampleFile()

Read a tab delimited sample file and for each non-comment, non-blank,
non header line, include a record of data in the returned array (ref) of
samples. Each line in order will be represented by a hash (ref) with the keys
'sample', 'flowcell', 'lane', and 'barcode'. If additional columns are present
in the file, a header line is required.

If a header is provided it must start with sample\\tflowcell\\tlane\\tbarcode
This way, each record will have an entry for each column, keyed by column name.

If the first line in a file looks like a header (i.e it contains the text
'sample' and 'flowcell' in that order, than it MUST be a real header line.

## getConfigOptions

    my %configOptHR = $self->loadConfig( $fileName );

Validates the filename as this is called early and the $fileName may be
an unvalidated options.

Returns a hash-ref of optionName => value entries.

Will die if can't find the config file specified, or if something happens
while parsing the config file (i.e. with Bio::Seqware::Config)

## loadOptions

    $self->loadOptions({ key => value, ... });

Valdates and loads the provided key => value settings into the object.
Returns nothing on success. As this does validation, it can die with lots of
different messages. It also does cross-validation and fills in implicit options, i.e. it sets
\--verbose if --debug was set.

## loadArguments

    $self->loadArguments(["arg1", "arg2"]);

Valdates and loads the CLI arguments (What is left over after removing options
up to and including a lone "--"). Returns nothing on success. As this does
validation, it can die with lots of different messages.

## validateCli

    $self->crossValidateCli()

Any validation involving more than one option, more than one argument, or
any combination of option and argument are vaildated here. That means all
argument-specific options have to be validated here.

## do\_launch

Called automatically by runner framework to implement the launch command.
Not intended to be called directly. Implemets the "launch" step of the
workflow.

Uses parseSampleFile() to generate a list to upload. Each entry in this list is
processed and upload independently as follows:

1\. \_launch\_prepareQueryInfo(): Adaptor mapping output hash from parseSampleFile
to input hash for dbGetBamFileInfo()

2\. dbGetBamFileInfo() is a fairly generic query into the database given 
a minimal hash of lookup data. It outputs a hash with a bunch of database data.
Data in the lookup set beyond what is required for retrieval is validated
against the database data retrieved when the keys match.

3\. \_launch\_prepareUploadInfo(): Adaptor mapping output hash from dbGetBamFileInfo
to input hash for dbinsertUpload.

4\. dbinsertUpload() Inserts the upload record for the above data and returns
the upload\_id inserted.

5\. The upload\_id is added to the data.

6\. dbinsertUploadFile() inserts the upoad file record 

7\. The upload record is marked as failed if an errors occured in 6 (Can't
record any errors earlier as the upload record does not yet exist. Otherwise
it is marked as done.

## do\_meta\_generate

Called automatically by runner framework to implement the meta-generate command.
Not intended to be called directly.

## do\_meta\_validate

Called automatically by runner framework to implement the meta-validate command.
Not intended to be called directly.

## do\_meta\_upload

Called automatically by runner framework to implement the meta-upload command.
Not intended to be called directly.

## do\_file\_upload

Called automatically by runner framework to implement the file\_upload command.
Not intended to be called directly.

## do\_status\_update

Called automatically by runner framework to implement the status-update command.
Not intended to be called directly.

## do\_status\_remote

Called automatically by runner framework to implement the status-remote command.
Not intended to be called directly.

## do\_status\_local

Called automatically by runner framework to implement the status-local command.
Not intended to be called directly.

## dbSetDone

    my $self->dbSetDone( $hashRef, $step );

Simple a wrapper for dbSetUploadStatus, returns the result of calling that with
the "upload\_id" key from the provided $hashRef and a new status of
"$step" . "\_done"

## dbSetFail

    my $self->dbSetDone( $hashRef, $step, $error );

A wrapper for dbSetUploadStatus, Calls that with the "upload\_id" key from the
provided $hashRef and a new status of
"$step" . "\_fail\_" . getErrorName( $error )

The $error will be return, but if an error occurs in trying to set fail, that
error will be \*prepended\* to $error before returning, separated with the string
"\\tTried to fail run because of:\\n"

## dbSetRunning

    my $uploadRec = dbSetRunning( $stepDone, $stepRunning )

Given the previous step and the next step, finds one record in the database
in state <$stepDone>\_done, sets its status to <$stepRunning>\_running, and
returns the equivqalent hash-ref. This is done in a transaction so it is safe
to run these steps overlapping each other.

## dbSetUploadStatus

    my $self->dbSetUploadStatus( $upload_id, $newStatus )

Changes the status of the specified upload record to the specified status.
Either returns 1 for success or dies with error.

## \_launch\_prepareQueryInfo

    my $queryHR = $self->_launch_translateToQueryInfo( $parsedUploadList );

Data processing step converting a hash obtained from parseSampleFile
to that useable by dbGetBamFileInfo. Used to isolate the code mapping the
headers from the file to columns in the database and to convert file value
representations to those used by the database. This is ill defined and a
potential change point.

## \_launch\_prepareUploadInfo

    my $uploadsAR = $self->_launch_prepareUploadInfo( $queryHR );

Data processing step converting a hash obtained from dbGetBamFileInfo
to that useable by dbInsertUpload(). Used to isolate the code mapping the
data recieved from the generic lookup routine to the specific upload
information needed by this program in managing uploads of bam files to cghub.
This is a potential change point.

## \_makeFileFromTemplate

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

## \_metaGenerate\_getDataPreservation

    my $preservation = $self->_metaGenerate_getDataPreservation( 'preservation );

If preservation contains "FFPE" (case insensitively), return 'FFPE' else
default to 'FROZEN';

## \_metaGenerate\_getDataLibraryPrep

    my $libraryPrep = $self->_metaGenerate_getDataLibraryPrep( $library_prep );

The library prep is either something containing the string TotalRNA, case
insensitively, in which case it is returned as is, or it is set to
Illumina TruSeq.

## \_metaGenerate\_getData

    $self->_metaGenerate_getData()

## \_metaGenerate\_getDataReadCount

    $ends = $self->_metaGenerate_getDataReadCount( $eperiment.sw_accession );

Returns 1 if single ended, 2 if paired-ended. Based on the number
of application reads in the associated experiment\_spot\_design\_read\_spec.
Dies if any other number found, or if any problem with db access.

## \_metaGenerate\_getDataReadGroup

    my $readGroup = $self->_metaGenerate_getDataReadGroup( $bamFile );

Gets the read group from the bam file using samtools and some unix tools.

## \_metaGenerate\_getDataReadLength

    $baseCountPerRead = _metaGenerate_getDataReadLength( $bam_file_path );

Examines first 1000 lines of the bam file and returns the length of the
longest read found.

## \_metaGenerate\_makeDataDir

    my $dataDir = $self->_metaGenerate_makeDataDir( $dataHR );

Creates the target data directory which should just be
catdir ($dataHR->{'metadata\_dir'}, $dataHR->{'cghub\_analysis\_id'});
The pre-existance of $dataHR->{'metadata\_dir'} is
checked. If succeeds, returns the name of the new dataDir, else dies
with error.

## \_metaGenerate\_linkBam

    my $bamLink = $self->_metaGenerate_linkBam( $dataHR );

Creates a link to $dataHR->{'file\_path'} in the $dataHR->{'dataDir'}.
The file\_path and the dataDir must exist. The link is named after the
<filename> extracted from the file\_path, The <file\_accession>, and the
<sample\_tcga\_uuid> as

    UNCID_<file_accession>.<sample_tcga_uuid>.<filename.

The link name only (no path) will be returned.

## \_metaValidate

    $self->_metaValidate( $uploadHR );

Validates the metadata to cghub for one run. Various parameters are hard coded
or passed as options.

## \_metaUpload

    $self->_metaUpload( $uploadHR );

Uploads the metadata to cghub for one run. Various parameters are hard coded
or passed as options.

## dbInsertUpload

    my $upload_id = $self->dbInsertUpload( $recordHR );

Inserts a new upload record. The associated upload\_file record will be added
by dbInsertUploadFile. Either succeeds or dies with error. All data for
upload must be in the provided hash, with the keys the field names from the
upload table.

Returns the id of the upload record inserted.

## dbDie

    $self->dbDie( $errorMessage );

Call to die due to a database error. Wraps a call to die with code to clean up
the database connection, rolling back any open transaction and closing and 
destroying the current database connection object.

It will check if a transaction was not finished and do a rollback, If that
was tried and failed, the error message will be appended with:
"Also:\\n\\tRollback failed because of:\\n$rollbackError", where $rollbackError
is the error caught during the attmptedrollback.

All errors during disconnect are ignored.

If the error thrown by dbDie is caught and handled, a new call to getDbh
will be needed as the old connection is no more.

## dbInsertUploadFile

    my $upload_id = $self->dbInsertUploadFile( $recordHR );

Inserts a new uploadFile record. The associated upload record must already
exist (i.e. have been inserted by dbInsertUpload). Either succeeds or
dies with error. All data for upload-file must be in the provided hash, with
the keys the field names from the uploadFile table.

Returns the id of the file record linked to.

## getDbh

    my $dbh = $self->getDbh();

Returns a cached database handle, create and cahcing a new one first if not
already existing. Creating requires appropriate parameters to be set and can
fail with a "DbConnectionException:...";

## dbGetBamFileInfo {

    $retrievedHR = $self->dbGetBamFileInfo( $lookupHR )

Looks up the bam file described by $lookupHR and returns a hash-ref of
information about it. Not very sophisticated. It requires the $lookupHR
t contain "sample", "flowcell", "lane\_index", "barcode", and "workflow\_id"
keys. If other keys are present, it will validate that retrieved
field with the same name have the same value; any differences is a fatal error.

Note that "barcode" should be undefined if looking up a non-barcoded lane, but
the key must be provided, and that lane\_index is used (0 based) not lane.

## fixupTildePath

    my $path = $self->fixupTildePath( $filePath );

Perl does not recognize the unix convention that file paths begining with
a tilde (~) are relative to the users home directory. This is function makes
that happen \*lexically\*. There is no validation that the output file or path
actually makes sense. If the the input path does not begin with a ~, it is
returned without change. Uses File::HomeDir to handle finding a home dir.

## getLogPrefix

    my $prefix = $self->getLogPrefix()

Create a prefix for logging messages, formatted as

     HOST TIMESTAMP RUN-UUID [LEVEL]

where timestamp formatted like getTimestamp, described herein and level is the
reporting level (INFO by default, or VERBOSE or DEBUG, if --verbose or --debug
reporting is specified by option.)

## logifyMessage

    my $logMessage = logifyMessage( $message );

Makes a message suitable for logging. It adds a prefix at the start of
every line and ensures the message ends with a newline. The prefix is by
provided by getLogPrefix. The prefix is separated from the message by a single
space, although any formating at the begining of a line is preserved, just
moved over by the length of the prefix (+ a space.)

## sayDebug

    $self->sayDebug("Something printed only if --debug was set.");
    $self->sayDebug("Something" $object );

Used to output text conditional on the --debug flag. Nothing is output if
\--debug is not set.

If the --log option is set, adds a prefix to each line of a message
using logifyMessage.

If an object parameter is passed, it will be printed on the following line.
Normal stringification is performed, so $object can be anything, including
another string, but if it is a hash-ref or an array ref, it will be formated
with Data::Dumper before printing.

See also say, sayVerbose.

## sayVerbose

    $self->sayVerbose("Something printed only if --verbose was set.");
    $self->sayVerbose("Something", $object);

Used to output text conditional on the --verbose flag. Nothing iw output if
\--verbose was not set. Note setting --debug automatically implies --verbose,
so sayVerbose will output text when --debug was set even if --verbose never
was expcicitly passed 

If the --log option is set, adds a prefix to each line of a message
using logifyMessage.

If an object parameter is passed, it will be printed on the following line.
Normal stringification is performed, so $object can be anything, including
another string, but if it is a hash-ref or an array ref, it will be formated
with Data::Dumper before printing.

See also say, sayDebug.

## say

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

## sayError

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
    $ cpanm https://github.com/theobio/p5-Bio-SeqWare-Uploads-CgHub-Bam/archive/v0.000.005.tar.gz

You can also manually download a release (zipped file) from github at
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

This module was developed for use with [SeqWare ](https://metacpan.org/pod/&#x20;http:#seqware.github.io).

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
