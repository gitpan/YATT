use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'YATT',
    license             => 'perl',
    dist_author         => '"KOBAYASI, Hiroaki" <hkoba@cpan.org>',
    dist_version_from   => 'lib/YATT.pm',
    requires => {
        'Test::More' => 0,
        'version'    => 0,
    },
    add_to_cleanup      => [ qw(YATT-* *.tmp) ],
);

$builder->create_build_script();
