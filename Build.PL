use 5.014;
use strict;
use warnings FATAL => 'all';
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Bio::SeqWare::Uploads::CgHub::Bam',
    license             => 'gpl',
    dist_author         => q{Stuart R. Jefferys <srjefferys (at) gmail (dot) com>},
    dist_version_from   => 'lib/Bio/SeqWare/Uploads/CgHub/Bam.pm',
    recursive_test_files => 1,
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::Exception'  => 0,
        'Test::Output'     => 0,
        'Test::MockModule' => 0,
        'DBD::Mock'        => 0,
    },
    requires => {
        'perl'          => '5.014',
        'File::HomeDir' => 0,
        'Data::GUID'    => 0,
    },
    add_to_cleanup     => [ 'p5-Bio-SeqWare-Uploads-CgHub-Bam-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
