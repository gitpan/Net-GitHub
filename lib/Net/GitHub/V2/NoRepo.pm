package Net::GitHub::V2::NoRepo;

use Any::Moose 'Role';

our $VERSION = '0.24';
our $AUTHORITY = 'cpan:FAYLAND';

use JSON::Any;
use WWW::Mechanize::GZip;
use MIME::Base64;
use HTTP::Request::Common;
use Carp qw/croak/;

# repo stuff
has 'owner' => ( isa => 'Str', is => 'ro', required => 1 );

# login
has 'login' => (is => 'rw', isa => 'Str', predicate => 'has_login',);
has 'token' => (is => 'rw', isa => 'Str', predicate => 'has_token',);

# api
has 'api_url' => ( is => 'ro', default => 'http://github.com/api/v2/json/');
has 'api_url_https' => ( is => 'ro', default => 'https://github.com/api/v2/json/');

has 'ua' => (
    isa     => 'WWW::Mechanize',
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $m    = WWW::Mechanize::GZip->new(
            agent       => "perl-net-github $VERSION",
            cookie_jar  => {},
            stack_depth => 1,
            keep_alive  => 4,
            timeout     => 60,
        );
        return $m;
    },
);

sub get {
    my $self = shift;

    my $resp = $self->ua->get(@_);
    croak $resp->as_string() unless ( $resp->is_success );
    return $resp->content();
}

has 'json' => (
    is => 'ro',
    isa => 'JSON::Any',
    lazy => 1,
    default => sub {
        return JSON::Any->new;
    }
);

sub get_json_to_obj {
    my ( $self, $pending_url, $key ) = @_;

    $pending_url =~ s!^/!!; # Strip leading '/'
    my $url  = $self->api_url . $pending_url;
    my $resp = $self->ua->get($url);
    return { error => '404 Not Found' } if $resp->code == 404;
    return { error => $resp->as_string() } unless ( $resp->is_success );
    my $json = $resp->content();
    my $data = $self->json->jsonToObj($json);

    return $data->{$key} if ( $key and exists $data->{$key} );
    return $data;
}

before get_json_to_obj_authed => sub {
    my $self = shift;

    return if $self->has_login and $self->has_token;

    eval { require Config::GitLike::Git; };
    return if $@;

    my $c = Config::GitLike::Git->new();
    $c->load;
    my $login = $c->get(key => 'github.user');
    my $token = $c->get(key => 'github.token');
    if ($login && $token) {
        $self->login($login);
        $self->token($token);
    }
};

sub get_json_to_obj_authed {
    push @_, 'POST';
    _get_json_to_obj_authed(@_);
}

sub get_json_to_obj_authed_PUT {
    push @_, 'PUT';
    _get_json_to_obj_authed(@_);
}

sub get_json_to_obj_authed_DELETE {
    push @_, 'DELETE';
    _get_json_to_obj_authed(@_);
}

sub _get_json_to_obj_authed {
    my $self = shift;
    my $pending_url = shift;
    
    my $request_method = pop @_; # can be DELETE or PUT

    croak 'login and token are required' unless ( $self->has_login and $self->has_token );

    $pending_url =~ s!^/!!; # Strip leading '/'
    my $url  = ( $pending_url =~ /^https?\:/ ) ? $pending_url :
        $self->api_url . $pending_url;

    my $key; # return $key from json obj
    if ( scalar @_ % 2 ) {
        $key = pop @_;
    }

    my $req = $request_method eq 'DELETE' ? HTTP::Request::Common::DELETE( $url, [ @_ ] ) :
              $request_method eq 'PUT'    ? HTTP::Request::Common::PUT( $url, [ @_ ] ) :
                                            HTTP::Request::Common::POST( $url, [ @_ ] );
    
    # "schacon/token:6ef8395fecf207165f1a82178ae1b984"
    my $auth_basic = $self->login . '/token:' . $self->token;
    $req->header('Authorization', 'Basic ' . encode_base64($auth_basic));
    
    my $res = $self->ua->request($req);
    return { error => '404 Not Found' } if $res->code == 404;

    my $json = $res->content();
    my $data = $self->json->jsonToObj($json);

    return $data->{$key} if ( $key and exists $data->{$key} );
    return $data;
}

sub args_to_pass {
    my $self = shift;
    my $ret;
    foreach my $col ('owner', 'login', 'token') {
        $ret->{$col} = $self->$col;
    }
    return $ret;
}

no Any::Moose;

1;
__END__

=head1 NAME

Net::GitHub::V2::NoRepo - Base role for Net::GitHub::V2, no repo access

=head1 SYNOPSIS

    package Net::GitHub::V2::XXX;

    use Any::Moose;
    with 'Net::GitHub::V2::NoRepo';

=head1 DESCRIPTION

If login and token are not given to new, the module will look in the B<.gitconfig> file if they are defined (see L<http://github.com/blog/180-local-github-config>).

=head1 ATTRIBUTES

=over 4

=item login

=item token

=back

=head1 METHODS

=over 4

=item ua

instance of L<WWW::Mechanize>

=item json

instance of L<JSON::Any>

=item get

handled by L<WWW::Mechanize>

=item get_json_to_obj

=item get_json_to_obj_authed

=back

=head1 AUTHOR

Fayland Lam, C<< <fayland at gmail.com> >>

Chris Nehren C<< apeiron@cpan.org >> refactored Net::GitHub::V2::Role to be
smarter about requiring a repo.

=head1 COPYRIGHT & LICENSE

Copyright 2009 Fayland Lam, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
