package Mason::Tidy::Compilation::InlinePerl;
use Mason::Tidy::Moose;
use Perl::Tidy qw();
extends 'Mason::Tidy::Compilation';

method handle_default () { }

method handle_block ($pos, $length, $block_type) {
    if ( $block_type eq 'perl' ) {

        # Get what's inside the <%perl> and </%perl> tags
        #
        $pos += length($block_type) + 3;
        $length -= ( length($block_type) * 2 + 7 );
        my $code = substr( $self->{source}, $pos, $length );
        if ( $code =~ /\n$/ ) {
            chomp($code);
            $length--;
        }
        $self->add_code( $code, $pos, $length, 'perl_block' );
    }
}

method handle_perl_line ($pos, $length) {
    $pos += 2;
    $length -= 2;
    my $code = substr( $self->{source}, $pos, $length );
    $self->add_code( $code, $pos, $length, 'perl_line' );
}

method add_code ($code, $pos, $length, $type) {
    my $marker = sprintf( "# %s\n", $self->unique_string );
    my $marked_code = $marker . $code . "\n" . $marker;
    $self->{untidied_code} .= $marked_code;
    push( @{ $self->{to_replace} }, [ $marker, $pos, $length, $type ] );
}

method replace_all () {
    my $adjust = 0;
    foreach my $repl ( @{ $self->{to_replace} } ) {
        my ( $marker, $pos, $length, $type ) = @$repl;
        my ($tidied) = ( $self->{tidied_code} =~ /$marker(.*)$marker/s )
          or die "could not find code delimited by '$marker': " . $self->{tidied_code};
        for ($tidied) { s/\s+$// }
        if ( $type eq 'perl_block' ) {
            for ($tidied) { s/^/  /gm }
        }
        substr( $self->{source}, $pos + $adjust, $length ) = $tidied;
        $adjust += ( length($tidied) - $length );
    }
}

method transform () {
    $self->parse;
    $self->{tidied_code} = $self->perltidy( $self->{untidied_code} );
    $self->replace_all;
}

method perltidy ($untidied) {
    my $tidied;
    Perl::Tidy::perltidy( source => \$untidied, destination => \$tidied, argv => '-noll -i=2' );
    return $tidied;
}

1;
