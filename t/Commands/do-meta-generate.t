#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

# Core
use File::Spec;                  # Generic file handling.
use File::Copy;                  # Copy a file
use Data::Dumper;                # Simple data structure printing
use Scalar::Util qw( blessed );  # Get class of objects
use File::Temp;                  # Simple transient files for testing

use Test::More 'tests' => 10;    # Main test module; run this many tests

# CPAN
use Test::Exception;             # Testing where code dies and errors
use Test::File::Contents;        # Comparing files
use Test::MockModule;            # Fake subroutine return values remotely

BEGIN {
    *CORE::GLOBAL::readpipe = \&mock_readpipe; # Must be before use
    require Bio::SeqWare::Uploads::CgHub::Bam;
}

# Mock system calls.
# Mock, set mock =1, unmock, set mock = 0.
# Mock one, set ret and exit
# Mock several, set session = [{ret=>, exit=>}, ...]
my $mock_readpipe = { 'mock' => 0, 'ret' => undef , 'exit' => 0, '_idx' => undef };

sub mock_readpipe {
    my $var = shift;
    my $retVal;
    if ( $mock_readpipe->{'mock'} ) {
        if (! $mock_readpipe->{'session'}) {
            $retVal = $mock_readpipe->{'ret'};
            $? = $mock_readpipe->{'exit'};
        }
        else {
            my @session = @{$mock_readpipe->{'session'}};
            my $idx = $mock_readpipe->{'_idx'};
            if (! defined $idx) {
                $idx = 0;
            }
            if ($idx >= @session) {
                die "Mock::ReadPipeException: Not enough session elements defined.\n";
            }
            $retVal = $mock_readpipe->{'session'}->[$idx]->{'ret'};
            $? = $mock_readpipe->{'session'}->[$idx]->{'exit'};
            $mock_readpipe->{'_idx'} += 1;
        }
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

my $SAMTOOLD_VIEW_HEADERS = 
"\@HD\tVN:1.0\tSO:unsorted
\@SQ\tSN:chr1\tLN:249250621
\@SQ\tSN:chr10\tLN:135534747
\@SQ\tSN:chr3\tLN:198022430
\@SQ\tSN:chr4\tLN:191154276
\@SQ\tSN:chr5\tLN:180915260
\@SQ\tSN:chr6\tLN:171115067
\@SQ\tSN:chr7\tLN:159138663
\@SQ\tSN:chr8\tLN:146364022
\@SQ\tSN:chr9\tLN:141213431
\@SQ\tSN:chrM_rCRS\tLN:16569
\@SQ\tSN:chrX\tLN:155270560
\@SQ\tSN:chrY\tLN:59373566
\@RG\tID:140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC\tPL:illumina\tPU:barcode\tLB:TruSeq\tSM:140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC
";

my $TEMP_DIR = File::Temp->newdir();  # Auto-delete self and contents when out of scope
my $DATA_DIR = File::Spec->catdir( "t", "Data", "Xml" );
my $GOOD_RUN_XML_FILE = File::Spec->catfile( $DATA_DIR, 'run.xml' );
my $GOOD_EXPERIMENT_XML_FILE = File::Spec->catfile( $DATA_DIR, 'experiment.xml' );
my $GOOD_ANALYSIS_XML_FILE = File::Spec->catfile( $DATA_DIR, 'analysis.xml' );
my $FAKE_BAM_FILE = File::Spec->catfile( $TEMP_DIR, 'fake.bam' );
copy($GOOD_RUN_XML_FILE, $FAKE_BAM_FILE) or die "Can't copy file for testing";

# Data for one sample

my $UPLOAD_HR = {
    'upload_id'         => 23985,
    'sample_id'         => 18254,
    'target'            => 'CGHUB',
    'status'            => 'CGHUB_Complete',
    'cghub_analysis_id' => '41a12166-ec7e-447b-94b2-9f3dd96401ca',
    'tstmp'             => '2014-08-13 10:06:46.949567',
    'metadata_dir'      => 'datastore/tcga/cghub/v2_uploads',
    'external_status'   => 'live',
};

my $LINK_NAME = 'UNCID_2462755.23b47813-7a77-44ca-b650-31a319c1f497.sorted_genome_alignments.bam';

my $RUN_HR = {
    'lane_accession'       => 2449977,
    'experiment_accession' => 975937,
    'sample_accession'     => 2449976,
};

my $ANALYSIS_HR = {
    'uploadIdAlias'      => 'upload_23985',
    'analysisDate'       => '2014-05-19T15:47:52.663',
    'workflow_accession' => 1015700,
    'tcga_uuid'          => '23b47813-7a77-44ca-b650-31a319c1f497',
    'lane_accession'     => 2449977,
    'readGroup'          => '140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC',
    'fileNoExtension'    => 'sorted_genome_alignments',
    'workflow_name'      => 'MapspliceRSEM',
    'workflow_version'   => '0.7.4',
    'workflow_algorithm' => 'samtools-sort-genome',
    'file_accession'     => 2462755,
    'file_md5sum'        => '04f5a22164bb399f61a2caee8ecb048b',
    'uncFileSampleName'  => $LINK_NAME,
};

my $EXPERIMENT_HR = {
    'experiment_accession'   => 975937,
    'sample_accession'       => 2449976,
    'experiment_description' => 'TCGA RNA-Seq Paired-End Experiment',
    'tcga_uuid'              => '23b47813-7a77-44ca-b650-31a319c1f497',
    'libraryPrep'            => 'Illumina TruSeq',
    'LibraryLayout'          => "PAIRED",
    'readEnds'               => 2,
    'baseCoord'              => 49,
    'instrument_model'       => 'Illumina HiSeq 2000',
    'preservation'           => 'FROZEN',
};

my %DATA = (%$UPLOAD_HR, %$RUN_HR, %$ANALYSIS_HR, %$EXPERIMENT_HR);
my $DATA_HR = \%DATA;

my $goodGetDataSelectElement = {
    'statement'    => qr/SELECT.*/msi,
    'bound_params' => [ $DATA_HR->{'upload_id'} ],
    'results'  => [[
        qw(
            file_timestamp
            workflow_accession
            file_accession
            file_md5sum
            file_path
            workflow_name
            workflow_version
            workflow_algorithm
            instrument_model
            lane_accession
            experiment_accession
            library_prep
            experiment_description
            experiment_id
            sample_accession
            tcga_uuid
            preservation
        )
    ], [
        '2014-05-19 15:47:52.663',
        1015700,
        2462755,
        '04f5a22164bb399f61a2caee8ecb048b',
        '/datastore/nextgenout4/seqware-analysis/illumina/140502_UNC12-SN629_0366_AC3UT1ACXX/seqware-0.7.0_Mapsplice-0.7.4/140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC/sorted_genome_alignments.bam',
        'MapspliceRSEM',
        '0.7.4',
        'samtools-sort-genome',
        'Illumina HiSeq 2000',
        2449977,
        975937,
        'TCGA RNA-Seq Multiplexed Paired-End Experiment on HiSeq 2000',
        'TCGA RNA-Seq Paired-End Experiment',
        72,
        2449976,
        '23b47813-7a77-44ca-b650-31a319c1f497',
        undef,
    ]]
};

subtest( '_metaGenerate_linkBam()' => \&test_linkBam );
subtest( '_metaGenerate_makeDataDir()' => \&test_makeDataDir );
subtest( '_metaGenerate_getDataReadLength()' => \&test_getDataReadLength );
subtest( '_metaGenerate_getDataReadCount()' => \&test_getDataReadCount );
subtest( '_metaGenerate_getDataReadGroup()' => \&test_getDataReadGroup );
subtest( '_metaGenerate_makeFileFromTemplate()' => \&test_makeFileFromTemplate );
subtest( '_metaGenerate_getDataPreservation()' => \&test_getDataPreservation );
subtest( '_metaGenerate_getDataLibraryPrep()' => \&test_getDataLibraryPrep );
subtest( '_metaGenerate_getData()' => \&test_getData );
subtest( 'do_meta_generate()' => \&test_do_meta_generate );

sub test_makeDataDir {
     plan( tests => 5 );

    {
        my $obj = makeBamForMetaGenerate();
        my $dataHR = { 'metadata_dir' => $TEMP_DIR, 'cghub_analysis_id' => $CLASS->getUuid() };
        my $want = File::Spec->catdir($dataHR->{'metadata_dir'}, $dataHR->{'cghub_analysis_id'});
        {
            ok( ! -d $want, "Directory doesn't pre-exist" );
        }
        my $got = $obj->_metaGenerate_makeDataDir( $dataHR );
        {
            is( $got, $want, "Created correct directory name" );
            ok( -d $got, "Directory now exists" );
        }
    }
    {
        my $message = "Fails if parent directory doesn't exist";
        my $obj = makeBamForMetaGenerate();
        my $dataHR = { 'cghub_analysis_id' => $TEMP_DIR, 'metadata_dir' => $CLASS->getUuid() };
        my $error1RES = "DirNotFoundException: Error looking up directory $dataHR->{'metadata_dir'}\. Error was:";
        my $errorRE = qr/^$error1RES\n\t/m;
        throws_ok( sub { $obj->_metaGenerate_makeDataDir( $dataHR ); }, $errorRE, $message );
    }
    {
        my $message = "Fails if parent directory not writeable";
        my $obj = makeBamForMetaGenerate();
        my $dataHR = { 'cghub_analysis_id' => $CLASS->getUuid(), 'metadata_dir' => File::Temp->newdir() };
        chmod( 0555, $dataHR->{'metadata_dir'} );
        my $want = File::Spec->catdir($dataHR->{'metadata_dir'}, $dataHR->{'cghub_analysis_id'});
        my $error1RES = 'CreateDirectoryException: Unable to create path "' . $want . '"\. Error was:';
        my $errorRE = qr/^$error1RES\n\t/m;
        throws_ok( sub { $obj->_metaGenerate_makeDataDir( $dataHR ); }, $errorRE, $message );
    }

}

sub test_linkBam {
    plan( tests => 6 );

    my $obj = makeBamForMetaGenerate();
    {
        my $dataHR = {
            'file_path' => $FAKE_BAM_FILE, 'dataDir' => $TEMP_DIR,
            'file_accession' => 111111, 'sample_tcga_uuid' => $CLASS->getUuid()
        };
        my $filename = 'fake.bam';
        my $wantLinkName = 'UNCID_111111.' . $dataHR->{'sample_tcga_uuid'} . ".$filename";
        my $wantLinkPath = File::Spec->catfile($dataHR->{'dataDir'}, $wantLinkName);
        {
            ok(! -l $wantLinkPath, "Link doesn't pre-exist");
        }
        {
            my $message = 'Link file name is returned correctly';
            my $want = $wantLinkName;
            my $got = $obj->_metaGenerate_linkBam( $dataHR );
            is($got, $want, $message);
        }
        {
            ok(-l $wantLinkPath, "Link is created");
            unlink( $wantLinkPath ) or die ("Deleting link $wantLinkPath failed. $!");
        }
    }
    {
        my $dataHR = {
            'file_path' => $CLASS->getUuid(), 'dataDir' => $TEMP_DIR,
            'file_accession' => 111111, 'sample_tcga_uuid' => $CLASS->getUuid()
        };
        {
            my $message = 'Error if file linked to does not exist';
            my $error1RES = 'FileNotFoundException: Error looking up file ' . $dataHR->{'file_path'} . '\. Error was:';
            my $errorRE = qr/^$error1RES\n\t/;
            throws_ok( sub { $obj->_metaGenerate_linkBam( $dataHR ); }, $errorRE, $message);
        }
    }
    {
        my $dataHR = {
            'file_path' => $FAKE_BAM_FILE, 'dataDir' => $CLASS->getUuid(),
            'file_accession' => 111111, 'sample_tcga_uuid' => $CLASS->getUuid()
        };
        {
            my $message = 'Error if dir link put in does not exist';
            my $error1RES = 'DirNotFoundException: Error looking up directory ' . $dataHR->{'dataDir'} . '\. Error was:';
            my $errorRE = qr/^$error1RES\n\t/;
            throws_ok( sub { $obj->_metaGenerate_linkBam( $dataHR ); }, $errorRE, $message);
        }
    }
    {
        my $dataHR = {
            'file_path' => $FAKE_BAM_FILE, 'dataDir' => File::Temp->newdir(),
            'file_accession' => 111111, 'sample_tcga_uuid' => $CLASS->getUuid()
        };
        my $filename = 'fake.bam';
        my $wantLinkName = 'UNCID_111111.' . $dataHR->{'sample_tcga_uuid'} . ".$filename";
        my $wantLinkPath = File::Spec->catfile($dataHR->{'dataDir'}, $wantLinkName);
        {
            my $message = 'Error if creating link fails';
            chmod( 0555, $dataHR->{'dataDir'} );
            my $error1RES = 'CreateLinkException: Could not create symlink:';
            my $error2RES = 'Link: "' . $wantLinkPath . '"';
            my $error3RES = 'Pointing to: "' . $dataHR->{'file_path'} . '"\. Error was:';
            my $errorRE = qr/^$error1RES\n\t$error2RES\n\t$error3RES/m;
            throws_ok( sub { $obj->_metaGenerate_linkBam( $dataHR ); }, $errorRE, $message);
        }
    }
}

sub test_getDataReadLength {
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
            my $error2RES = "FileNotFoundException: Error looking up file $badFileName\. Error was:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES\n\t/;
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
            my $error2RES = "ValueNotDefinedException: Expected a defined value\.";
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

sub test_getDataReadCount {
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

sub test_getDataReadGroup {
    plan( tests => 7);

    # Good test
    {
        my $obj = makeBamForMetaGenerate();
        my $anyRealFileName = $GOOD_RUN_XML_FILE;
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = "$SAMTOOLD_VIEW_HEADERS";

        {
            my $message = "Returns correct read group";

            # Read group expected given $SAMTOOLD_VIEW_HEADERS
            my $want = "140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC";
            my $got = $obj->_metaGenerate_getDataReadGroup( $anyRealFileName );
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
            my $error1RES = "ReadGroupException: Can't determine read group because:";
            my $error2RES = "FileNotFoundException: Error looking up file $badFileName\. Error was:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES\n\t/;
            throws_ok( sub { $obj->_metaGenerate_getDataReadGroup( $badFileName ); }, $matchRE, $message );
        }
    }

    # Bad - Undefined file path
    {
        my $obj = makeBamForMetaGenerate();
        my $badFileName = undef;
        {
            my $message = "Error if provided filename undefined";
            my $error1RES = "ReadGroupException: Can't determine read group because:";
            my $error2RES = "ValueNotDefinedException: Expected a defined value\.";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES/;
            throws_ok( sub { $obj->_metaGenerate_getDataReadGroup( $badFileName ); }, $matchRE, $message );
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
            my $error1RES = "ReadGroupException: Can't determine read group because:";
            my $error2RES = "SamtoolsFailedException: Error getting read group\. Exit error code: 27\. Failure message was:";
            my $error3RES = "Original command was:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES\n.*\n\t$error3RES/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadGroup( $anyRealFileName ); }, $matchRE, $message );
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
            my $error1RES = "ReadGroupException: Can't determine read group because:";
            my $error2RES = "SamtoolsExecNoOutputException: Neither error nor result generated\. Strange\.";
            my $error3RES = "Original command was:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES\n.*\n\t$error3RES/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadGroup( $anyRealFileName ); }, $matchRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }

    # Bad - Too many read groups found
    {
        my $obj = makeBamForMetaGenerate();
        my $anyRealFileName = $GOOD_RUN_XML_FILE;
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $SAMTOOLD_VIEW_HEADERS . $SAMTOOLD_VIEW_HEADERS;

        {
            my $message = "Error if get mre than one read group line.";
            my $error1RES = "ReadGroupException: Can't determine read group because:";
            my $error2RES = "ReadGroupNumberException: One and only one readgroup allowed. Found 2 lines:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadGroup( $anyRealFileName ); }, $matchRE, $message );
        }
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'mock'} = 1;
    }
    # Bad - No read groups found
    {
        my $obj = makeBamForMetaGenerate();
        my $anyRealFileName = $GOOD_RUN_XML_FILE;
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = "This is not the expected output.";

        {
            my $message = "Error if get no read group line.";
            my $error1RES = "ReadGroupException: Can't determine read group because:";
            my $error2RES = "ReadGroupNumberException: One and only one readgroup allowed. Found 0 lines:";
            my $matchRE = qr/^$error1RES.*\n\t$error2RES/m;
            throws_ok( sub { $obj->_metaGenerate_getDataReadGroup( $anyRealFileName ); }, $matchRE, $message );
        }
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'mock'} = 1;
    }


}

sub test_getDataPreservation {
    plan( tests => 4);

    {
        my $message = "Undefined is FROZEN";
        my $want = "FROZEN";
        my $obj = makeBamForMetaGenerate();
        my $got = $obj->_metaGenerate_getDataPreservation();
        is( $got, $want, $message);
    }
    {
        my $message = "Empty string is FROZEN";
        my $want = "FROZEN";
        my $obj = makeBamForMetaGenerate();
        my $got = $obj->_metaGenerate_getDataPreservation( "" );
        is( $got, $want, $message);
    }
    {
        my $message = "ffpe is FFPE";
        my $want = "FFPE";
        my $obj = makeBamForMetaGenerate();
        my $got = $obj->_metaGenerate_getDataPreservation( "ffpe" );
        is( $got, $want, $message);
    }
    {
        my $message = "anything_else is FROZEN";
        my $want = "FROZEN";
        my $obj = makeBamForMetaGenerate();
        my $got = $obj->_metaGenerate_getDataPreservation( "Anything else?" );
        is( $got, $want, $message);
    }
 
}

sub test_getDataLibraryPrep {
    plan( tests => 4);

    {
        my $message = "Undefined is 'Illumina TruSeq'";
        my $want = 'Illumina TruSeq';
        my $obj = makeBamForMetaGenerate();
        my $got = $obj->_metaGenerate_getDataLibraryPrep();
        is( $got, $want, $message);
    }
    {
        my $message = "Empty string is 'Illumina TruSeq'";
        my $want = 'Illumina TruSeq';
        my $obj = makeBamForMetaGenerate();
        my $got = $obj->_metaGenerate_getDataLibraryPrep( "" );
        is( $got, $want, $message);
    }
    {
        my $message = "'totalrna' is totalrna";
        my $want = "totalrna";
        my $obj = makeBamForMetaGenerate();
        my $got = $obj->_metaGenerate_getDataLibraryPrep( 'totalrna' );
        is( $got, $want, $message);
    }
    {
        my $message = "anything_else is 'Illumina TruSeq'";
        my $want = 'Illumina TruSeq';
        my $obj = makeBamForMetaGenerate();
        my $got = $obj->_metaGenerate_getDataLibraryPrep( "Anything else?" );
        is( $got, $want, $message);
    }
 
}

sub test_getData {
    plan( tests => 4 );

    my $badDupSelectElement = {
        'statement'    => qr/SELECT.*/msi,
        'bound_params' => [ $DATA_HR->{'upload_id'} ],
        'results'  => [[
            qw(
                file_timestamp
                workflow_accession
                file_accession
                file_md5sum
                file_path
                workflow_name
                workflow_version
                workflow_algorithm
                instrument_model
                lane_accession
                experiment_accession
                library_prep
                experiment_description
                experiment_id
                sample_accession
                tcga_uuid
                preservation
            )
        ], [
            '2014-05-19 15:47:52.663',
            1015700,
            2462755,
            '04f5a22164bb399f61a2caee8ecb048b',
            '/datastore/nextgenout4/seqware-analysis/illumina/140502_UNC12-SN629_0366_AC3UT1ACXX/seqware-0.7.0_Mapsplice-0.7.4/140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC/sorted_genome_alignments.bam',
            'MapspliceRSEM',
            '0.7.4',
            'samtools-sort-genome',
            'Illumina HiSeq 2000',
            2449977,
            975937,
            'TCGA RNA-Seq Multiplexed Paired-End Experiment on HiSeq 2000',
            'TCGA RNA-Seq Paired-End Experiment',
            72,
            2449976,
            '23b47813-7a77-44ca-b650-31a319c1f497',
            undef,
        ], [
            '2014-05-19 15:47:52.663',
            1015700,
            2462755,
            '04f5a22164bb399f61a2caee8ecb048b',
            '/datastore/nextgenout4/seqware-analysis/illumina/140502_UNC12-SN629_0366_AC3UT1ACXX/seqware-0.7.0_Mapsplice-0.7.4/140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC/sorted_genome_alignments.bam',
            'MapspliceRSEM',
            '0.7.4',
            'samtools-sort-genome',
            'Illumina HiSeq 2000',
            2449977,
            975937,
            'TCGA RNA-Seq Multiplexed Paired-End Experiment on HiSeq 2000',
            'TCGA RNA-Seq Paired-End Experiment',
            72,
            2449976,
            '23b47813-7a77-44ca-b650-31a319c1f497',
            undef,
        ]]
    };


    {
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('_metaGenerate_getDataReadGroup', sub { return '140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC'; } );
        $module->mock('_metaGenerate_getDataReadLength', sub { return '49' } );
        $module->mock('_metaGenerate_getDataReadCount', sub { return '2' } );

        my $obj = makeBamForMetaGenerate();
        my @dbSession = ($goodGetDataSelectElement);
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "Good run", @dbSession );
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'session'} = [
            { 'ret' => "$SAMTOOLS_RETURN", 'exit' => 0 },
            { 'ret' => "$SAMTOOLD_VIEW_HEADERS", 'exit' => 0 },
        ];
        my $got = $obj->_metaGenerate_getData( $UPLOAD_HR );
        my $want = $DATA_HR;
        {
            is_deeply($got, $want, "Return value correct");
        }
        $mock_readpipe->{'session'} = undef;
        $mock_readpipe->{'_idx'} = undef;
        $mock_readpipe->{'mock'} = 0;
    }

    {
        my $message = "Two is too many";
        my @dbSession = ($badDupSelectElement);
        my $obj = makeBamForMetaGenerate();
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "Two is too many", @dbSession );
        my $error1RES = "MetaDataGenerateException: Failed collecting data for template use\. Error was:";
        my $error2RES = "DbDuplicateRecordException: Data record retrieved should be unique:";
        my $error3RES = "Dulicate data record 1:";
        my $error4RES = "Dulicate data record 2:";
        my $errorRE = qr/^$error1RES\n\t$error2RES\n\t$error3RES\n\t.*\n$error4RES/ms;
        throws_ok( sub {$obj->_metaGenerate_getData( $UPLOAD_HR );}, $errorRE, $message);
    }

    {
        my $message = "One read count is bad.";
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('_metaGenerate_getDataReadGroup', sub { return '140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC'; } );
        $module->mock('_metaGenerate_getDataReadLength', sub { return '49' } );
        $module->mock('_metaGenerate_getDataReadCount', sub { return '1' } );

        my $obj = makeBamForMetaGenerate();
        my @dbSession = ($goodGetDataSelectElement);
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "Good run", @dbSession );
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'session'} = [
            { 'ret' => "$SAMTOOLS_RETURN", 'exit' => 0 },
            { 'ret' => "$SAMTOOLD_VIEW_HEADERS", 'exit' => 0 },
        ];

        my $error1RES = "MetaDataGenerateException: Failed collecting data for template use. Error was:";
        my $error2RES = 'BadReadEnds: Only paired end \(2 reads\) allowed, not 1\.';
        my $errorRE = qr/^$error1RES\n\t$error2RES/ms;
        throws_ok( sub {$obj->_metaGenerate_getData( $UPLOAD_HR );}, $errorRE, $message);
        $mock_readpipe->{'session'} = undef;
        $mock_readpipe->{'_idx'} = undef;
        $mock_readpipe->{'mock'} = 0;
    }

    {
        my $message = "Fails if uploadHR input data doesn't match retrieved data.";
        my %upload = %$UPLOAD_HR;
        # Set a value that will confilct with data. This could happen if upload
        # table schema changes, or faulty programming was added to handle data
        # processing and assignement.
        $upload{'tcga_uuid'} = "Not the correct value";
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('_metaGenerate_getDataReadGroup', sub { return '140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC'; } );
        $module->mock('_metaGenerate_getDataReadLength', sub { return '49' } );
        $module->mock('_metaGenerate_getDataReadCount', sub { return '2' } );

        my $obj = makeBamForMetaGenerate();
        my @dbSession = ($goodGetDataSelectElement);
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "Good run", @dbSession );
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'session'} = [
            { 'ret' => "$SAMTOOLS_RETURN", 'exit' => 0 },
            { 'ret' => "$SAMTOOLD_VIEW_HEADERS", 'exit' => 0 },
        ];

        my $error1RES = "MetaDataGenerateException: Failed collecting data for template use. Error was:";
        my $error2RES = 'BadDataException: template data and upload data different. Mismatch was:';
        my $errorRE = qr/^$error1RES\n\t$error2RES/ms;
        throws_ok( sub {$obj->_metaGenerate_getData( \%upload );}, $errorRE, $message);
        $mock_readpipe->{'session'} = undef;
        $mock_readpipe->{'_idx'} = undef;
        $mock_readpipe->{'mock'} = 0;
    }

}

sub test_makeFileFromTemplate {
    plan( tests => 20);

    my $obj = makeBamForMetaGenerate();
    # run.xml
    {

        my $sampleFileName = File::Spec->catfile( "t", "Data", "Xml", "run.xml" );
        my $outFileName = File::Spec->catfile( "$TEMP_DIR", "run.xml" );
        my $templateFileName = File::Spec->catfile($obj->{'templateBaseDir'}, $obj->{'xmlSchema'}, "run.xml.template" );

        # Files for use by test are available
        {
            ok( (-f $templateFileName), "Can find run.xml.template");
            ok( (-f $sampleFileName), "Can find run.xml example");
        }

        # Absolute paths
        {
            my $runXml = $obj->_metaGenerate_makeFileFromTemplate( $RUN_HR, $outFileName, $templateFileName );
            {
                is ( $runXml, $outFileName, "Appeared to create run.xml file");
                ok( (-f $runXml),   "Can find run.xml file");
                files_eq_or_diff( $runXml, $sampleFileName, "run.xml file generated correctly." );
            }
        }

        # Relatve template path
        {
            my $runXml = $obj->_metaGenerate_makeFileFromTemplate( $RUN_HR, $outFileName, 'run.xml.template' );
            {
                is ( $runXml, $outFileName, "Appeared to create run.xml file");
                ok( (-f $runXml),   "Can find run.xml file");
                files_eq_or_diff( $runXml, $sampleFileName, "run.xml file generated correctly." );
            }
        }

        # Error during processing.
        {
            my $message = "Error if fails during template processing";
            my $errorRES1 = 'FileFromTemplateException: Failed creating file ".+run\.xml" from template ".+run\.xml\.template"\. Error was:\n\t';
            my $errorRE = qr/^$errorRES1/;
            throws_ok( sub { $obj->_metaGenerate_makeFileFromTemplate( "BAD", $outFileName, $templateFileName );}, $errorRE, $message);
        }
        {
            my $message = "Error if template processing failw without error";
            my $module = new Test::MockModule('Template');
            $module->mock('process', sub { return; } );
            my $errorRES1 = 'FileFromTemplateException: Failed creating file ".+run\.xml" from template ".+run\.xml\.template"\. Error was:\n\t';
            my $errorRE = qr/^$errorRES1/;
            throws_ok( sub { $obj->_metaGenerate_makeFileFromTemplate( "BAD", $outFileName, $templateFileName );}, $errorRE, $message);
        }
    }

    # analysis.xml
    {

        my $sampleFileName = File::Spec->catfile( "t", "Data", "Xml", "analysis.xml" );
        my $outFileName = File::Spec->catfile( "$TEMP_DIR", "analysis.xml" );
        my $templateFileName = File::Spec->catfile($obj->{'templateBaseDir'}, $obj->{'xmlSchema'}, "analysis.xml.template" );

        # Files for use by test are available
        {
            ok( (-f $templateFileName), "Can find analysis.xml.template");
            ok( (-f $sampleFileName), "Can find analysis.xml example");
        }

        # Absolute paths
        {
            my $analysisXml = $obj->_metaGenerate_makeFileFromTemplate( $ANALYSIS_HR, $outFileName, $templateFileName );
            {
                is ( $analysisXml, $outFileName, "Appeared to create analysis.xml file");
                ok( (-f $analysisXml),   "Can find analysis.xml file");
                files_eq_or_diff( $analysisXml, $sampleFileName, "analysis.xml file generated correctly." );
            }
        }
    }

    # experment.xml
    {

        my $sampleFileName = File::Spec->catfile( "t", "Data", "Xml", "experiment.xml" );
        my $outFileName = File::Spec->catfile( "$TEMP_DIR", "experiment.xml" );
        my $templateFileName = File::Spec->catfile($obj->{'templateBaseDir'}, $obj->{'xmlSchema'}, "experiment.xml.template" );

        # Files for use by test are available
        {
            ok( (-f $templateFileName), "Can find experiment.xml.template");
            ok( (-f $sampleFileName), "Can find experiment.xml example");
        }

        # Absolute paths
        {
            my $experimentXml = $obj->_metaGenerate_makeFileFromTemplate( $EXPERIMENT_HR, $outFileName, $templateFileName );
            {
                is ( $experimentXml, $outFileName, "Appeared to create experiment.xml file");
                ok( (-f $experimentXml),   "Can find experiment.xml file");
                files_eq_or_diff( $experimentXml, $sampleFileName, "experiment.xml file generated correctly." );
            }
        }
    }
}

sub test_do_meta_generate {
    plan( tests => 6);

    {
        # Mock EVERYTHING.
        my %upload = %$UPLOAD_HR;
        my %data = %$DATA_HR;
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        my $obj = makeBamForMetaGenerate();
        $module->mock('dbSetRunning', sub { return \%upload; } );
        $module->mock('_metaGenerate_getData', sub { return \%data; } );
        $module->mock('_metaGenerate_makeDataDir', sub { return "/dev/null"; } );
        $module->mock('_metaGenerate_linkBam', sub { return "not_a_File"; } );
        $module->mock('_metaGenerate_makeFileFromTemplate', sub { 1 } );
        $module->mock('dbSetDone', sub { 1 } );
        {
            my $message = "Returns 1 on success, if all internals mocked.";
            my $got = $obj->do_meta_generate();
            my $want = 1;
            is($got, $want, $message);
        }
    }

    {
        # Should only run very first step, then exit succesfully
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('dbSetRunning', sub { return; } );
        $module->mock('_metaGenerate_getData', sub { die "NO RUN I" } );
        my $obj = makeBamForMetaGenerate();
        {
            my $message = "Does not run anything if has no launch record.";
            my $got = $obj->do_meta_generate();
            my $want = 1;
            is($got, $want, $message);
        }
    }

    # Mock everything except SetRunning and SetDone, Script DB for
    # succesful run.
    {
        my %upload = %$UPLOAD_HR;
        my %data = %$DATA_HR;
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('_metaGenerate_getData', sub { return \%data; } );
        $module->mock('_metaGenerate_makeDataDir', sub { return "/dev/null"; } );
        $module->mock('_metaGenerate_linkBam', sub { return "not_a_File"; } );
        $module->mock('_metaGenerate_makeFileFromTemplate', sub { 1 } );
        my $obj = makeBamForMetaGenerate();
        my @dbEvents_ok = (
            dbMockStep_Begin(),
            dbMockStep_SetTransactionLevel(),
            {
                'statement'   => qr/SELECT \* FROM upload WHERE status = /msi,
                'bound_params' => [ 'launch_done' ],
                'results'  => [
                    ['upload_id', 'status', 'sample_id' ],
                    [$upload{'upload_id'}, 'launch_done', $upload{'sample_id'}],
                ],
            },
            {
                'statement'   => qr/UPDATE upload SET status = .*/msi,
                'bound_params' => [ 'meta-generate_running', $upload{'upload_id'} ],
                'results'  => [ [ 'rows' ], [] ],
            },
            dbMockStep_Commit(),
            {
                'statement'   => qr/UPDATE upload SET status = .*/msi,
                'bound_params' => [ 'meta-generate_done', $upload{'upload_id'} ],
                'results'  => [ [ 'rows' ], [] ],
            },
        );
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'setRunWithReturn', @dbEvents_ok );
        {
            my $message = "Returns 1 on success when setRunning and setDone used for real";
            my $got = $obj->do_meta_generate();
            my $want = 1;
            is($got, $want, $message);
        }
    }

    {
        # Mock everything except getData.
        my %upload = %$UPLOAD_HR;
        my %data = %$DATA_HR;
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        my $obj = makeBamForMetaGenerate();
        $module->mock('dbSetRunning', sub { return \%upload; } );
        $module->mock('_metaGenerate_makeDataDir', sub { return "/dev/null"; } );
        $module->mock('_metaGenerate_linkBam', sub { return "not_a_File"; } );
        $module->mock('_metaGenerate_makeFileFromTemplate', sub { 1 } );
        $module->mock('dbSetDone', sub { 1 } );

        # Need to mock some getData internals also...
        $module->mock('_metaGenerate_getDataReadGroup', sub { return '140502_UNC12-SN629_0366_AC3UT1ACXX_4_CAGATC'; } );
        $module->mock('_metaGenerate_getDataReadLength', sub { return '49' } );
        $module->mock('_metaGenerate_getDataReadCount', sub { return '2' } );
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'session'} = [
            { 'ret' => "$SAMTOOLS_RETURN", 'exit' => 0 },
            { 'ret' => "$SAMTOOLD_VIEW_HEADERS", 'exit' => 0 },
        ];
        my @dbSession = ($goodGetDataSelectElement);
        $obj->{'dbh'}->{'mock_session'} = DBD::Mock::Session->new( "Good run", @dbSession );
        {
            my $message = "Returns 1 on success when getData used for real";
            my $got = $obj->do_meta_generate();
            my $want = 1;
            is($got, $want, $message);
        }
        # restore backtick mocking defaults - needs to be a module?
        $mock_readpipe->{'session'} = undef;
        $mock_readpipe->{'_idx'} = undef;
        $mock_readpipe->{'mock'} = 0;
    }


    {
        my %upload = %$UPLOAD_HR;
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('_metaGenerate_getData', sub { die "KaboomException: Bang.\n"; } );
        my $obj = makeBamForMetaGenerate();
        my @dbEvents_ok = (
            dbMockStep_Begin(),
            dbMockStep_SetTransactionLevel(),
            {
                'statement'   => qr/SELECT \* FROM upload WHERE status = /msi,
                'bound_params' => [ 'launch_done' ],
                'results'  => [
                    ['upload_id', 'status', 'sample_id' ],
                    [$upload{'upload_id'}, 'launch_done', $upload{'sample_id'}],
                ],
            },
            {
                'statement'   => qr/UPDATE upload SET status = .*/msi,
                'bound_params' => [ 'meta-generate_running', $upload{'upload_id'} ],
                'results'  => [ [ 'rows' ], [] ],
            },
            dbMockStep_Commit(),
            {
                'statement'   => qr/UPDATE upload SET status = .*/msi,
                'bound_params' => [ 'meta-generate_failed_Kaboom', $upload{'upload_id'} ],
                'results'  => [ [ 'rows' ], [] ],
            },
        );
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'setRunWithReturn', @dbEvents_ok );
        {
            my $message = "Sets fail and dies if does not complete normally.";
            my $errorRE = qr/^KaboomException: Bang\.\n$/;
            throws_ok(sub {$obj->do_meta_generate();}, $errorRE, $message );
        }
    }
    {
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('dbSetRunning', sub { die "KaboomException: Bang.\n"; } );
        my $obj = makeBamForMetaGenerate();
        {
            my $message = "Sets fail and dies if does not complete normally.";
            my $errorRE = qr/^KaboomException: Bang\.\n\tAlso: upload data not available\n/;
            throws_ok(sub {$obj->do_meta_generate();}, $errorRE, $message );
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
sub dbMockStep_Begin {
    return {
        'statement' => 'BEGIN WORK',
        'results'   => [ [] ],
    };
}

sub dbMockStep_SetTransactionLevel {
    return {
        'statement' => 'SET TRANSACTION ISOLATION LEVEL SERIALIZABLE',
        'results'  => [ [] ],
    };
}

sub dbMockStep_Commit {
    return {
        'statement' => 'COMMIT',
        'results'   => [ [] ],
    };
}

sub dbMockStep_Rollback {
    return {
        'statement' => 'ROLLBACK',
        'results'   => [ [] ],
    };
}
