#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

use Cwd;                         # get current working directory.

use Test::More 'tests' => 12;    # Main test module; run this many tests
use Test::Exception;             # Testing where code dies and errors
use Test::MockModule;            # Fake subroutine return values remotely


BEGIN {
    *CORE::GLOBAL::readpipe = \&mock_readpipe; # Must be before use
    require Bio::SeqWare::Uploads::CgHub::Bam;
}

# Mock system calls.
# Mock, set mock =1, unmock, set mock = 0.
# Mock one, set ret and exit
# Mock several, set session = [{ret=>, exit=>}, ...]
my $mock_readpipe = { 'mock' => 0, 'ret' => undef , 'exit' => 0, '_idx' => undef, 'argAR' => undef };

sub mock_readpipe {
    my $var = shift;
    my $retVal;
    if ( $mock_readpipe->{'mock'} ) {
        if (! $mock_readpipe->{'session'}) {
            $retVal = $mock_readpipe->{'ret'};
            if (defined $retVal && ref ($retVal) eq 'CODE') {
               if (defined $mock_readpipe->{'argAR'}) {
                   $retVal =  &$retVal(@{$mock_readpipe->{'argAR'}});
               }
               else {
                  $retVal =  &$retVal();
               }
            }
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
my @DEF_CLI = qw(--dbUser dummy --dbPassword dummy --dbHost dummy --dbSchema dummy file-upload);
my $GOOD_BAM_UPLOAD = "Fake (GOOD) Submission Return\n"
                      . "100.000.\n";

my $REPEAT_BAM_UPLOAD = "Fake (BAD) Submission Return\n"
                      . "Error    : Your are attempting to upload to a uuid"
                      . " which already exists within the system and is not"
                      . " in the submitted or uploading state. This is not allowed.\n";

my $BAD_BAM_UPLOAD = "Fake (UNKNOWN) Submission Return\n"
                      . "This is not the result you are looking for.\n";

my $UPLOAD_HR = {
    'upload_id' => -5,
    'metadata_dir' => "t",
    'cghub_analysis_id' => 'Data',
    'status' => 'file-upload_done'
};

# Good tests for _fileUpload
{
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $GOOD_BAM_UPLOAD;
        my $obj = makeBamForFileUpload();
        {
            my $shows = "Success when returns valid message";
            my $got = $obj->_fileUpload( $UPLOAD_HR );
            my $want = 1;
            is( $got, $want, $shows);
        }
        $mock_readpipe->{'mock'} = 0;
    }
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $GOOD_BAM_UPLOAD;
        my $obj = makeBamForFileUpload();
        {
            my $shows = "Directory doesn't change";
            my $want = getcwd();
            $obj->_fileUpload( $UPLOAD_HR );
            my $got = getcwd();
            is( $got, $want, $shows);
        }
        $mock_readpipe->{'mock'} = 0;
    }
}

# Errors from _fileUpload
{
    # $? not 0 (indicating failure) and text returned
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $BAD_BAM_UPLOAD;
        $mock_readpipe->{'exit'} = 99;
        my $obj = makeBamForFileUpload();
        {
            my $message = "Fails when update call errors, with error message";
            my $errorRES1 = "FileUploadExec-99-WithOutputException: Exited with error value \"99\"\.";
            my $errorRES2 = "Output was:";
            my $errorRES3 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2.*\n\t$errorRES3/ms;
            throws_ok( sub {$obj->_fileUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }

    # $? not 0 (indicating failure) and no text returned
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'exit'} = 88;
        my $obj = makeBamForFileUpload();
        {
            my $message = "Fails when file-upload call errors without error message";
            my $errorRES1 = "FileUploadExec-88-NoOutputException: Exited with error value \"88\"\.";
            my $errorRES2 = "No output was generated\.";
            my $errorRES3 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2\n\t$errorRES3/ms;
            throws_ok( sub {$obj->_fileUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }

    # $? not 0 (indicating failure) and "repeated upload" text returned.
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $REPEAT_BAM_UPLOAD;
        $mock_readpipe->{'exit'} = 77;
        my $obj = makeBamForFileUpload();
        {
            my $message = "Fails when file-upload call errors, with error message";
            my $errorRES1 = "FileUploadExec-77-RepeatException: Already submitted. Exited with error value \"77\"\.";
            my $errorRES2 = "Output was:";
            my $errorRES3 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2.*\n\t$errorRES3/ms;
            throws_ok( sub {$obj->_fileUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }
    # $? is 0 (indicating success) but no text returned.
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = undef;
        $mock_readpipe->{'exit'} = 0;
        my $obj = makeBamForFileUpload();
        {
            my $message = "Fails when file-upload call succeeds but without any response";
            my $errorRES1 = "FileUploadExecNoOutputException: Neither error nor result generated\. Strange\.";
            my $errorRES2 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2/ms;
            throws_ok( sub {$obj->_fileUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }
    # $? is 0 (indicating success) but unexpected text is returned.
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $BAD_BAM_UPLOAD;
        $mock_readpipe->{'exit'} = 0;
        my $obj = makeBamForFileUpload();
        {
            my $message = "Fails when file-upload call succeeds but with incorrect response";
            my $errorRES1 = "FileUploadExecUnexpectedOutput: Apparently failed to validate\.";
            my $errorRES2 = "Output was:";
            my $errorRES3 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2.*\n\t$errorRES3/ms;
            throws_ok( sub {$obj->_fileUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }
    # $? is 0 (indicating success) but "repeated upload" text is returned.
    {
        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $REPEAT_BAM_UPLOAD;
        $mock_readpipe->{'exit'} = 0;
        my $obj = makeBamForFileUpload();
        {
            my $message = "Fails when file-upload call succeeds but returns REPEATED response";
            my $errorRES1 = "FileUploadExecRepeatException: Already submitted\. Exited with success though\. Strange\.";
            my $errorRES2 = "Output was:";
            my $errorRES3 = "Original command was:";
            my $errorRE = qr/^$errorRES1\n\t$errorRES2.*\n\t$errorRES3/ms;
            throws_ok( sub {$obj->_fileUpload( $UPLOAD_HR );}, $errorRE, $message );
        }
        $mock_readpipe->{'mock'} = 0;
        $mock_readpipe->{'exit'} = 0;
    }

}


# Good run of do_file_upload
{
    {
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('dbSetRunning', sub { return $UPLOAD_HR; } );
        $module->mock('dbSetDone', sub { 1 } );
        my $obj = makeBamForFileUpload();

        $mock_readpipe->{'mock'} = 1;
        $mock_readpipe->{'ret'} = $GOOD_BAM_UPLOAD;
        {
            my $message = "Normal run of do_file_upload.";
            my $got = $obj->do_file_upload();
            my $want = 1;
            is($got, $want, $message);
        }
        $mock_readpipe->{'mock'} = 0;
    }
    {
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('dbSetRunning', sub { return; } );
        my $obj = makeBamForFileUpload();
        {
            my $message = "Normal run of do_file_upload, Nothing to do.";
            my $got = $obj->do_file_upload();
            my $want = 1;
            is($got, $want, $message);
        }
    }
}

# Bad run of do_file_upload, mocking upload status changes, with uploadHR
{
    {
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('_fileUpload', sub { die "KaboomException: Bang.\n"; } );
        my $obj = makeBamForFileUpload();
        my @dbEvents_ok = (
            dbMockStep_Begin(),
            dbMockStep_SetTransactionLevel(),
            {
                'statement'   => qr/SELECT \* FROM upload WHERE status = /msi,
                'bound_params' => [ 'meta-upload_done' ],
                'results'  => [
                    ['upload_id', 'status', 'metadata_dir', 'cghub_analysis_id'],
                    [$UPLOAD_HR->{'upload_id'}, 'meta-upload_done', "t", 'Data'],
                ],
            },
            {
                'statement'   => qr/UPDATE upload SET status = .*/msi,
                'bound_params' => [ 'file-upload_running', $UPLOAD_HR->{'upload_id'} ],
                'results'  => [ [ 'rows' ], [] ],
            },
            dbMockStep_Commit(),
            {
                'statement'   => qr/UPDATE upload SET status = .*/msi,
                'bound_params' => [ 'file-upload_failed_Kaboom', $UPLOAD_HR->{'upload_id'} ],
                'results'  => [ [ 'rows' ], [] ],
            },
        );
        $obj->{'dbh'}->{'mock_session'} =
            DBD::Mock::Session->new( 'setRunWithReturn', @dbEvents_ok );
        {
            my $message = "Bad run of do_file_upload with upload data.";
            my $errorRE = qr/^KaboomException: Bang\.\n$/;
            throws_ok(sub {$obj->do_file_upload();}, $errorRE, $message );
        }
    }
    {
        my $module = new Test::MockModule('Bio::SeqWare::Uploads::CgHub::Bam');
        $module->mock('dbSetRunning', sub { die "KaboomException: Bang.\n"; } );
        my $obj = makeBamForFileUpload();
        {
            my $message = "Bad run of do_file_upload with no upload data.";
            my $errorRE = qr/^KaboomException: Bang\.\n\tAlso: upload data not available\n/;
            throws_ok(sub {$obj->do_file_upload();}, $errorRE, $message );
        }
    }
}

sub makeBamForFileUpload {

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