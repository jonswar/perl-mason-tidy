package Mason::Tidy::Compilation::PlainText;
use File::Slurp;
use HTML::PullParser;
use Mason::Tidy::Moose;
extends 'Mason::Tidy::Compilation';

method conceal_all () {
    my $adjust = 0;
    foreach my $entry ( @{ $self->{to_conceal} } ) {
        my ( $pos, $length, $type, $subst ) = @$entry;
        $self->{concealed}->{$subst} =
          { type => $type, text => substr( $self->{source}, $pos + $adjust, $length ) };
        substr( $self->{source}, $pos + $adjust, $length ) = $subst;
        $adjust += ( length($subst) - $length );
    }
}

method handle_block ()          { $self->handle_non_plain_text( @_, 'block' ) }
method handle_component_call () { $self->handle_non_plain_text( @_, 'component_call' ) }
method handle_perl_line ()      { $self->handle_non_plain_text( @_, 'perl_line' ) }
method handle_substitution ()   { $self->handle_non_plain_text( @_, 'substitution' ) }

method handle_non_plain_text ($pos, $length, $type) {
    my $subst = sprintf( "<!--%s-->", $self->unique_string );
    push( @{ $self->{to_conceal} }, [ $pos, $length, $type, $subst ] );
}

method handle_plain_text ($pos, $length) {
}

method reveal_all () {
    while ( my ( $subst, $repl ) = each( %{ $self->{concealed} } ) ) {
        my $type = $repl->{type};
        my $text = $repl->{text};
        if ( $type eq 'perl_line' || $type eq 'block' ) {
            $self->{source} =~ s/^\s*$subst/$text/m;
        }
        else {
            $self->{source} =~ s/$subst/$text/;
        }
    }
}

method transform () {
    $self->parse;
    $self->conceal_all;
    $self->tidy_html;
    $self->reveal_all;
}

method tidy_html () {
    my $p = HTML::PullParser->new(
        doc             => $self->{source},
        start           => '"S", text',
        end             => '"E", text',
        default         => '"O", text',
        ignore_elements => [qw(script style)],
    ) || die "Can't open: $!";
    my $lineno = 0;
    my @deltas;

    while ( my $token = $p->get_token ) {
        my ( $type, $text ) = @$token;
        $deltas[$lineno]++ if $type eq 'S';
        $deltas[$lineno]-- if $type eq 'E';
        $lineno += ( $text =~ tr/\n// );
    }
    my $level  = 0;
    my $result = '';
    my @lines  = split( "\n", $self->{source} );
    for ( my $lineno = 0 ; $lineno < @deltas ; $lineno++ ) {
        my $delta = $deltas[$lineno] || 0;
        $level += $delta if $delta < 0;
        $result .= scalar( '  ' x $level ) . $lines[$lineno] . "\n";
        $level += $delta if $delta > 0;
    }
    $self->{source} = $result;
}

1;
