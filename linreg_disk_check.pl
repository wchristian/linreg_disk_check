use strictures;
use IO::All -binary;
use Capture::Tiny 'capture';
use Cpanel::JSON::XS qw' encode_json decode_json ';
use Statistics::LSNoHistory;
use List::Util 'min';

run();

sub run {
    my %fs_pcts    = drive_stats();
    my $resolution = 300;
    my $now        = time - time % $resolution;
    my @data       = update_db( $now, $resolution, %fs_pcts );
    my $step_count = 5;
    my @scales     = 0 .. 2;
    predict( $_, $step_count, $now, $resolution, @data ) for @scales;
    return;
}

sub drive_stats {
    my ( undef, @fs_lines ) = split /\n/, safe_system( "df -P" );
    my %seen;
    my %fs_pcts = map {
        my ( $fs_name, $size, $used, undef, undef, $path ) = split /\s+/, $_;
        ( "$path $fs_name", $used / $size );
    } @fs_lines;
    return %fs_pcts;
}

sub safe_system {
    my ( $cmd ) = @_;
    my ( $out, $err, $ret ) = capture { system $cmd};
    die "process failed:\nout:\n$out\nerr:\n$err\nret:\n$ret\n" if $ret or $err;
    return $out;
}

sub update_db {
    my ( $now, $resolution, %fs_pcts ) = @_;
    my $file    = "drives.json";
    my @data    = @{ -e $file ? decode_json io( $file )->all : [] };
    my $prev_ts = ( @data && $data[0][0] ) || ( $now - $resolution );
    exit if $now - $prev_ts < $resolution;

    while ( $now - $prev_ts > 2 * $resolution ) {    # fill gaps if necessary
        unshift @data, [ $prev_ts + $resolution, {} ];
        $prev_ts = $data[0][0];
    }
    unshift @data, [ $now, \%fs_pcts ];
    pop @data if @data > 1000;
    io( $file )->print( encode_json \@data );
    return @data;
}

sub predict {
    my ( $scale, $step_count, $now, $resolution, @data ) = @_;
    my $step_size = $step_count**$scale;
    my ( %names, @samples );
    for my $i ( 0 .. ( $step_size * $step_count ) - 1 ) {
        my $sample = $data[$i];
        next if not $sample;
        push @{ $samples[ int $i / $step_size ] }, $sample;
        $names{$_} = 1 for keys %{ $sample->[1] };
    }
    return if @samples < 2;

    my $future = $now + $resolution * $step_count**( $scale + 1 );    # look ahead as far as we look back
    for my $name ( sort keys %names ) {
        my @points = map condense_sample_set( $name, @{$_} ), @samples;
        my $linreg = Statistics::LSNoHistory->new( points => \@points );
        next if not                                                   # sometimes linreg doesn't like the data,
          my $y_in_future = eval { $linreg->predict( $future ) };     # i think when it's too flat
        next if $y_in_future < 1;

        while ( 1 ) {    # step back to report a full-by date more accurately
            my $step_back = $future - ( $resolution / 2 );
            my $new_y = $linreg->predict( $step_back );
            last if $new_y < 1;
            $future      = $step_back;
            $y_in_future = $new_y;
        }
        my $msg = "$name expected to reach $y_in_future on scale $scale by " . localtime( $future );
        system( "powershell Set-ExecutionPolicy -Scope Process RemoteSigned ; ./toast.ps1 $msg" );
    }
    return;
}

sub condense_sample_set {
    my ( $name, @sample_set ) = @_;
    my $time_stamp = $sample_set[0][0];
    my @values     = map $_->[1]{$name}, @sample_set;
    my $avg        = min @values;
    return ( $time_stamp, $avg );
}
