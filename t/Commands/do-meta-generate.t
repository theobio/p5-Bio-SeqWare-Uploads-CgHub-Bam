#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

use Test::More 'tests' => 2;     # Main test module; run this many tests
use Test::Exception;

BEGIN {
    *CORE::GLOBAL::readpipe = \&mock_readpipe; # Must be before use
    require Bio::SeqWare::Uploads::CgHub::Bam;
}

# Mock system calls.
my $mock_readpipe = { 'mock' => 0, 'ret' => undef , 'exit' => 0 };

sub mock_readpipe {
    my $var = shift;
    my $retVal;
    if ( $mock_readpipe->{'mock'} ) {
        $retVal = $mock_readpipe->{'ret'};
        $? = $mock_readpipe->{'exit'};
    }
    else {
        $retVal = CORE::readpipe($var);
    }
    return $retVal;
}

my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';
my @DEF_CLI = qw(--dbUser dummy --dbPassword dummy --dbHost dummy --dbSchema dummy --workflow_id 38 meta-generate);
my $SAMTOOLS_RETURN = 
"TTAGATAAAGGATACTG
AAAAGATAAGGATA
GCCTAAGCTAA
ATAGCTTCAGC
TAGGC
CAGCGGCAT
";

my $DATA_DIR = File::Spec->catdir( "t", "Data", "Xml" );
my $GOOD_RUN_XML_FILE = File::Spec->catfile( $DATA_DIR, 'run.xml' );
my $GOOD_EXPERIMENT_XML_FILE = File::Spec->catfile( $DATA_DIR, 'experiment.xml' );
my $GOOD_ANALYSIS_XML_FILE = File::Spec->catfile( $DATA_DIR, 'analysis.xml' );


subtest( '_metaGenerate_getDataReadLength()' => \&test_metaGenerate_getDataReadLength );
subtest( '_metaGenerate_getDataReadCount()' => \&test_metaGenerate_getDataReadCount );


sub test_metaGenerate_getDataReadLength {
    plan( tests => 6);

    # Good test
    {
        my $obj = makeBamForMetaGenerate();
        my $anyRealFileName = $GOOD_RUN_XML_FILE;
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = "$SAMTOOLS_RETURN";

        {
            my $message = "Returns correct read length";
            my $want = 17; # Length of longest line in $SAMTOOLS_RETURN
            my $got = $obj->_metaGenerate_getDataReadLength( $anyRealFileName );
            is( $got, $want, $message);
        }
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'mock'} = 1;
    }

    # Bad - No file path found
    {
        my $obj = makeBamForMetaGenerate();
        my $badFileName = $obj->getUuid() . ".bam";
        {
            my $message = "Error if provided filename not real.";
            my $error1RES = "ReadLengthException: Can't determine bam max read length because:";
            my $error2RES = "BadParameterException: No such File:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES/;
            throws_ok( sub { $obj->_metaGenerate_getDataReadLength( $badFileName ); }, $matchRE, $message );
        }
    }

    # Bad - Undefined file path
    {
        my $obj = makeBamForMetaGenerate();
        my $badFileName = undef;
        {
            my $message = "Error if provided filename undefined";
            my $error1RES = "ReadLengthException: Can't determine bam max read length because:";
            my $error2RES = "BadParameterException: Bam file name undefined\.";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES/;
            throws_ok( sub { $obj->_metaGenerate_getDataReadLength( $badFileName ); }, $matchRE, $message );
        }
    }

    # Bad - Samtools failed with error exit.
    {
        my $obj = makeBamForMetaGenerate();
        my $anyRealFileName = $GOOD_RUN_XML_FILE;
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'exit'} = 27;
        {
            my $message = "Error if Samtools failes with error exit";
            my $error1RES = "ReadLengthException: Can't determine bam max read length because:";
            my $error2RES = "SamtoolsFailedException: Error getting reads\. Exit error code: 27\. Failure message was:";
            my $error3RES = "Original command was:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES\n.*\n\t$error3RES/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadLength( $anyRealFileName ); }, $matchRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }

    # Bad - Samtools produced no output.
    {
        my $obj = makeBamForMetaGenerate();
        my $anyRealFileName = $GOOD_RUN_XML_FILE;
        $mock_readpipe->{'mock'} = 1;
        {
            my $message = "Error if Samtools succceds but returns nothing";
            my $error1RES = "ReadLengthException: Can't determine bam max read length because:";
            my $error2RES = "SamtoolsExecNoOutputException: Neither error nor result generated\. Strange\.";
            my $error3RES = "Original command was:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES\n.*\n\t$error3RES/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadLength( $anyRealFileName ); }, $matchRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }

    # Bad - Read length too short
    {
        my $obj = makeBamForMetaGenerate();
        my $anyRealFileName = $GOOD_RUN_XML_FILE;
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = "AATTGG\n1234567890123456\n";

        {
            my $message = "Error if read length of returned string is <17.";
            my $error1RES = "ReadLengthException: Can't determine bam max read length because:";
            my $error2RES = "SamtoolsShortReadException: Max read length to short, was: 16";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadLength( $anyRealFileName ); }, $matchRE, $message );
        }
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'mock'} = 1;
    }
}

sub test_metaGenerate_getDataReadCount {
    plan( tests => 5);

    # Lookup returns valid value - 2
    {
        my $experimentId = 5;
        my $readEnds = 2;
        my @dbSession = ({
            'statement'    => qr/SELECT count\(\*\) as read_ends.*/msi,
            'bound_params' => [ $experimentId ],
            'results'  => [ ['read_ends'], [$readEnds], ]
        });
        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "readEnds", @dbSession );
        {
            my $message = "Read end query returns valid value: 2";
            my $want = $readEnds;
            my $got = $obj->_metaGenerate_getDataReadCount( $experimentId );
            is( $got, $want, $message);
        }
    }

    {
        my $experimentId = 5;
        my $readEnds = 1;
        my @dbSession = ({
            'statement'    => qr/SELECT count\(\*\) as read_ends.*/msi,
            'bound_params' => [ $experimentId ],
            'results'  => [ ['read_ends'], [$readEnds], ]
        });
        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "readEnds", @dbSession );
        {
            my $message = "Read end query returns valid value: 1";
            my $want = $readEnds;
            my $got = $obj->_metaGenerate_getDataReadCount( $experimentId );
            is( $got, $want, $message);
        }
   }

   # Lookup returns invalid value - 0
   {
        my $experimentId = 5;
        my $readEnds = 0;
        my @dbSession = ({
            'statement'    => qr/SELECT count\(\*\) as read_ends.*/msi,
            'bound_params' => [ $experimentId ],
            'results'  => [ ['read_ends'], [$readEnds], ]
        });
        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "readEnds", @dbSession );
        {
            my $message = "Read end query returns invalid value: 0";
            my $errorRES1 = "DbReadCountException: Failed to retrieve the number of reads\. Error was:";
            my $errorRES2 = "DbDataError: Found $readEnds read ends, expected 1 or 2\.";
            my $matchRE = qr/^$errorRES1.*\n\t$errorRES2/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadCount( $experimentId ); }, $matchRE, $message);
        }
   }

   # Lookup returns invalid value - 3
   {
        my $experimentId = 5;
        my $readEnds = 3;
        my @dbSession = ({
            'statement'    => qr/SELECT count\(\*\) as read_ends.*/msi,
            'bound_params' => [ $experimentId ],
            'results'  => [ ['read_ends'], [$readEnds], ]
        });
        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "readEnds", @dbSession );
        {
            my $message = "Read end query returns invalid value: 3";
            my $errorRES1 = "DbReadCountException: Failed to retrieve the number of reads\. Error was:";
            my $errorRES2 = "DbDataError: Found $readEnds read ends, expected 1 or 2\.";
            my $matchRE = qr/^$errorRES1.*\n\t$errorRES2/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadCount( $experimentId ); }, $matchRE, $message);
        }
   }

   # Lookup returns invalid value - undef
   {
        my $experimentId = 5;
        my @dbSession = ({
            'statement'    => qr/SELECT count\(\*\) as read_ends.*/msi,
            'bound_params' => [ $experimentId ],
            'results'  => [ [] ]
        });
        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "readEnds", @dbSession );
        {
            my $message = "Read end query returns invalid value: undef";
            my $errorRES1 = "DbReadCountException: Failed to retrieve the number of reads\. Error was:";
            my $errorRES2 = "DbLookupError: Nothing retrieved from database\.";
            my $matchRE = qr/^$errorRES1.*\n\t$errorRES2/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadCount( $experimentId ); }, $matchRE, $message);
        }
   }

}


# Data providers

sub makeBamForMetaGenerate {

    @ARGV = @DEF_CLI;
    my $obj = $CLASS->new();
    $obj->{'dbh'} = makeMockDbh();
    return $obj;
}

sub makeMockDbh {
    my $mockDbh = DBI->connect(
        'DBI:Mock:',
        '',
        '',
        { 'RaiseError' => 1, 'PrintError' => 0, 'AutoCommit' => 1, 'ShowErrorStatement' => 1 },
    );

    return $mockDbh;
}
