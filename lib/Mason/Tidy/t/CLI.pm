package Mason::Tidy::t::CLI;
use Capture::Tiny qw(capture_merged);
use File::Slurp;
use File::Temp qw(tempdir);
use Mason::Tidy;
use IPC::System::Simple qw(capturex);
use Test::Class::Most parent => 'Test::Class';

sub test_get_options : Tests {
    my $try = sub {
        my ( $argv, $expect_params, $expect_result ) = @_;
        my %params;
        my $result = Mason::Tidy->get_options( $argv, \%params );
        cmp_deeply( \%params, $expect_params, "params" );
        is( $result ? 1 : 0, $expect_result ? 1 : 0, "result" );
    };
    $try->( [], {}, 1 );
    $try->( [qw(--indent-perl-block 2 -r)], { indent_perl_block => 2, replace => 1 }, 1 );
    my $out =
      capture_merged { $try->( [qw(--indent-perl-block 2 --bad)], { indent_perl_block => 2 }, 0 ) };
    like( $out, qr/Unknown option: bad/ );
}

sub test_cli : Tests {
    my $out;

    $out = capture_merged { system( $^X, "bin/masontidy", "-h" ) };
    like( $out, qr/masontidy - Tidy/ );

    my $tempdir = tempdir( 'name-XXXX', TMPDIR => 1, CLEANUP => 1 );
    write_file( "$tempdir/comp1.mc", "<%2+2%>" );
    write_file( "$tempdir/comp2.mc", "<%4+4%>" );
    $out = capture_merged {
        system( $^X, "bin/masontidy", "-r", "$tempdir/comp1.mc", "$tempdir/comp2.mc" );
    };
    is( read_file("$tempdir/comp1.mc"), "<% 2 + 2 %>", "comp1" );
    is( read_file("$tempdir/comp2.mc"), "<% 4 + 4 %>", "comp2" );

    write_file( "$tempdir/comp1.mc", "<%2+2%>" );
    $out = capture_merged {
        system( $^X, "bin/masontidy", "$tempdir/comp1.mc" );
    };
    is( $out, "<% 2 + 2 %>" );
    is( read_file("$tempdir/comp1.mc"), "<%2+2%>", "comp1" );

    $out = capture_merged {
        system( $^X, "bin/masontidy", "$tempdir/comp1.mc", "$tempdir/comp2.mc" );
    };
    like( $out, qr/must pass -r/ );
}

1;
