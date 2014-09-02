#! /usr/bin/env perl

use Test::More 'tests' => 1;     # Main test module; run this many subtests
use Scalar::Util qw( blessed );  # Get class of objects

use Bio::SeqWare::Uploads::CgHub::Bam;
my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';

# Run these tests
subtest( 'new()' => \&testNew );

sub testNew {
    plan( tests => 1 );

    my $obj = $CLASS->new();
    {
        my $message = "Returns object of correct type";
        my $want = $CLASS;
        my $got = blessed( $obj );
        is( $got, $want, $message );
    }
}