#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

use Test::More 'tests' => 6;     # Main test module; run this many tests
use Test::Exception;
use DBD::Mock;                   # Fake database results
use File::Spec;              # Generic file handling.

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