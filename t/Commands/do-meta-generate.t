#! /usr/bin/env perl
use 5.014;
use strict;
use warnings FATAL => 'all';

use Test::More 'tests' => 1;     # Main test module; run this many tests

# This class tests ...
use Bio::SeqWare::Uploads::CgHub::Bam;
my $CLASS = 'Bio::SeqWare::Uploads::CgHub::Bam';

{
    my $message = "no option, no argument";
    @ARGV = ('meta-generate');
    my $obj = $CLASS->new();
    {
        $message .= " smoke test";
        ok( $obj->do_meta_generate() );
    }
}
