#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

use Test::More 'tests' => 13;     # Main test module; run this many tests
use Test::Exception;
use DBD::Mock;                   # Fake database results
use File::Spec;              # Generic file handling.
use Data::Dumper;

# This class tests ...
use Bio::SeqWare::Uploads::CgHub::Bam;

my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';
my $SAMPLE_FILE_BAM = File::Spec->catfile( "t", "Data", "samplesToUpload.txt" );
my @DEF_CLI = (qw(--dbUser dummy --dbPassword dummy --dbHost dummy --dbSchema dummy --workflow_id 38 launch ), $SAMPLE_FILE_BAM);


# Tests for _launch_insertUpload()
{
    my $mockUploadId = 21;
    my $recHR = {
        sample_id => 19,
        target => 'CGHUB_BAM',
        status => 'launch_running',
        cghub_analysis_id => $CLASS->getUuid(),
        metadata_dir=>'/datastore/tcga/cghub/v2_uploads'
    };

    # valid run.
    {
        my @dbEvent = ({
            'statement'   => qr/INSERT INTO upload.*/msi,
            'bound_params' => [ $recHR->{sample_id},
                                $recHR->{target},
                                $recHR->{status},
                                $recHR->{cghub_analysis_id},
                                $recHR->{metadata_dir}],
            'results'  => [[ 'upload_id' ], [ $mockUploadId ]],
        });
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'newUploadRecord', @dbEvent );
        {
            my $message = "_launch_insertUpload with good data works.";
            my $got = $obj->_launch_insertUpload( $recHR );
            my $want = $mockUploadId;
            is( $got, $want, $message );
        }
    }

    # DB error.
    {
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{mock_add_resultset} = {
            sql => "INSERT INTO upload ( sample_id, target, status, cghub_analysis_id, metadata_dir)
         VALUES ( ?, ?, ?, ?, ? )
         RETURNING upload_id",
            results => DBD::Mock->NULL_RESULTSET,
            failure => [ 5, 'Ooops.' ],
        };
        {
            my $message = "_launch_insertUpload fails if db throws error.";
            my $error1RES = 'dbUploadInsertException: Insert of new upload record failed\. Error was:';
            my $error2RES = 'Ooops\.';
            my $errorRE = qr/$error1RES\n.*$error2RES/m;
            throws_ok( sub { $obj->_launch_insertUpload( $recHR ); }, $errorRE, $message);
        }
    }

    # Bad returned results.
    {
        my @dbEvent = ({
            'statement'    => qr/INSERT INTO upload.*/msi,
            'bound_params' => [ $recHR->{sample_id},
                                $recHR->{target},
                                $recHR->{status},
                                $recHR->{cghub_analysis_id},
                                $recHR->{metadata_dir},
                              ],
            'results'  => [],
        });
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'newUploadRecord', @dbEvent );
        {
            my $message = "_launch_insertUpload fails if db returns unexpected results.";
            my $error1RES = 'dbUploadInsertException: Insert of new upload record failed\. Error was:';
            my $error2RES = 'Id of the upload record inserted was not retrieved\.';
            my $errorRE = qr/$error1RES\n$error2RES/m;
            throws_ok( sub { $obj->_launch_insertUpload( $recHR ); }, $errorRE, $message);
        }
    }
}

# Tests for _launch_insertUploadFile()
{
    my $recHR = {
        upload_id => 21,
        file_id => 5,
    };

    # valid run.
    {
        my @dbEvent = ({
            'statement'   => qr/INSERT INTO upload_file.*/msi,
            'bound_params' => [ $recHR->{upload_id},
                                $recHR->{file_id},
                              ],
            'results'  => [[ 'file_id' ], [ $recHR->{file_id} ]],
        });
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'newUploadFileRecord', @dbEvent );
        {
            my $message = "_launch_insertUploadFile with good data works.";
            my $got = $obj->_launch_insertUploadFile( $recHR );
            my $want = $recHR->{file_id};
            is( $got, $want, $message );
        }
    }

    # DB error.
    {
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{mock_add_resultset} = {
            sql =>  "INSERT INTO upload_file ( upload_id, file_id)
         VALUES ( ?, ? )
         RETURNING file_id",
            results => DBD::Mock->NULL_RESULTSET,
            failure => [ 5, 'Ooops.' ],
        };
        {
            my $message = "_launch_insertUploadFile fails if db throws error.";
            my $error1RES = 'dbUploadFileInsertException: Insert of new upload_file record failed. Error was:';
            my $error2RES = 'Ooops\.';
            my $errorRE = qr/$error1RES\n.*$error2RES/m;
            throws_ok( sub { $obj->_launch_insertUploadFile( $recHR ); }, $errorRE, $message);
        }
    }

    # Bad returned results.
    {
        my @dbEvent = ({
            'statement'    => qr/INSERT INTO upload_file.*/msi,
            'bound_params' => [ $recHR->{upload_id},
                                $recHR->{file_id},
                              ],
            'results'  => [],
        });
        my $obj = makeBamForlaunch();
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'newUploadFileRecord', @dbEvent );
        {
            my $message = "_launch_insertUploadFile fails if db returns unexpected results.";
            my $error1RES = 'dbUploadFileInsertException: Insert of new upload_file record failed\. Error was:';
            my $error2RES = 'Id of the file record linked to was not retrieved\.';
            my $errorRE = qr/$error1RES\n$error2RES/m;
            throws_ok( sub { $obj->_launch_insertUploadFile( $recHR ); }, $errorRE, $message);
        }
    }
}

# Testing _launch_prepareQueryInfo
{
    my $obj = makeBamForlaunch();
    my $inputDAT = $obj->parseSampleFile();
    {
        my $message = "Line 1 of sample file converted correctly for Query.";
        my $got = $obj->_launch_prepareQueryInfo( $inputDAT->[0] );
        my $want = { 'sample' => 'TCGA1', 'flowcell' => 'UNC1', 'workflow_id' => 38,
            'lane' => 6, 'lane_index' => 5, 'barcode' => undef,
            'file_path' => undef, 'bam_file' => undef };
        is_deeply( $got, $want, $message);
    }
    {
        my $message = "Line 2 of sample file converted correctly for Query, file_path";
        my $lookupHR = $inputDAT->[1];
        my %lookup = %$lookupHR;
        $lookup{'file_path'} = $lookup{'bam_file'};
        delete( $lookup{'bam_file'} );
        my $got = $obj->_launch_prepareQueryInfo( \%lookup );
        my $want = { 'sample' => 'TCGA2', 'flowcell' => 'UNC2', 'workflow_id' => 38,
            'lane' => 7, 'lane_index' => 6, 'barcode' => 'ATTCGG',
            'file_path' => undef };
        is_deeply( $got, $want, $message);
    }
    {
        my $message = "Line 2 of sample file converted correctly for Query, no file";
        my $lookupHR = $inputDAT->[1];
        my %lookup = %$lookupHR;
        delete( $lookup{'bam_file'} );
        my $got = $obj->_launch_prepareQueryInfo( \%lookup );
        my $want = { 'sample' => 'TCGA2', 'flowcell' => 'UNC2', 'workflow_id' => 38,
            'lane' => 7, 'lane_index' => 6, 'barcode' => 'ATTCGG' };
        is_deeply( $got, $want, $message);
    }
    {
        my $message = "Line 3 of sample file converted correctly for Query.";
        my $got = $obj->_launch_prepareQueryInfo( $inputDAT->[2] );
        my $want = { 'sample' => 'TCGA3', 'flowcell' => 'UNC3', 'workflow_id' => 38,
             'lane' => 8, 'lane_index' => 7, 'barcode' => 'ATTCGG',
             'file_path' => '/not/really', 'bam_file' => '/not/really' };
        is_deeply( $got, $want, $message);
    }
    {
        my $message = "Line 4 of sample file converted correctly for Query.";
        my $got = $obj->_launch_prepareQueryInfo( $inputDAT->[3] );
        my $want = { 'sample' => 'TCGA4', 'flowcell' => 'UNC4', 'workflow_id' => 38,
             'lane' => 1, 'lane_index' => 0, 'barcode' => undef,
             'file_path' => '/old/fake', 'bam_file' => '/old/fake' };
        is_deeply( $got, $want, $message);
        
    }
}

# Testing _launch_prepareUploadInfo
{
    my $obj = makeBamForlaunch();
    my $inputHR = { 'sample_id' => 19, 'file_id' => 5,
             'lane_index' => 0, 'barcode' => 'ATGATG', 'file_path' => '/old/fake'  };
    my $forUploadHR = $obj->_launch_prepareUploadInfo( $inputHR );
    {
        my $message = "uuid added for upload";
        my $matchRE = qr/^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/;
        like ($forUploadHR->{'cghub_analysis_id'}, $matchRE, $message);
    }
    {
        my $message = "Rest of upload record correct";
        my %got = %$forUploadHR;
        delete $got{'cghub_analysis_id'};
        my %want = ('sample_id' => 19, 'target' => 'CGHUB_BAM', 'file_id' => 5,
        'status' => 'launch_running', 'metadata_dir' => '/datastore/tcga/cghub/v2_uploads' );
        is_deeply( \%got, \%want, $message)
    }
}

sub makeBamForlaunch {

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