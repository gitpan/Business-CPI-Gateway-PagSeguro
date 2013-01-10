package Business::CPI::Gateway::PagSeguro;
# ABSTRACT: Business::CPI's PagSeguro driver

use Moo;
use XML::LibXML;
use Carp;
use LWP::Simple ();
use URI;
use URI::QueryParam;
use DateTime;
use Locale::Country ();
use Data::Dumper;

extends 'Business::CPI::Gateway::Base';

our $VERSION = '0.66'; # VERSION

has '+checkout_url' => (
    default => sub { 'https://pagseguro.uol.com.br/v2/checkout/payment.html' },
);

has '+currency' => (
    default => sub { 'BRL' },
);

has base_url => (
    is => 'ro',
    default => sub { 'https://ws.pagseguro.uol.com.br/v2' },
);

has token => (
    is  => 'ro',
);

sub get_notifications_url {
    my ($self, $code) = @_;

    return $self->_build_uri("/transactions/notifications/$code");
}

sub get_transaction_details_url {
    my ($self, $code) = @_;

    return $self->_build_uri("/transactions/$code");
}

sub get_transaction_query_url {
    my ($self, $info) = @_;

    $info ||= {};

    my $final_date   = $info->{final_date}   || DateTime->now(time_zone => 'local'); # XXX: really local?
    my $initial_date = $info->{initial_date} || $final_date->clone->subtract(days => 30);

    my $new_info = {
        initialDate    => $initial_date->strftime('%Y-%m-%dT%H:%M'),
        finalDate      => $final_date->strftime('%Y-%m-%dT%H:%M'),
        page           => $info->{page} || 1,
        maxPageResults => $info->{rows} || 1000,
    };

    return $self->_build_uri('/transactions', $new_info);
}

sub query_transactions { goto \&get_and_parse_transactions }

sub get_and_parse_notification {
    my ($self, $code) = @_;

    my $xml = $self->_load_xml_from_url(
        $self->get_notifications_url($code)
    );

    if ($self->log->is_debug) {
        $self->log->debug("The notification we received was:\n" . Dumper($xml));
    }

    return $self->_parse_transaction($xml);
}

sub notify {
    my ($self, $req) = @_;

    if ($req->params->{notificationType} eq 'transaction') {
        my $code = $req->params->{notificationCode};

        $self->log->info("Received notification for $code");

        my $result = $self->get_and_parse_notification( $code );

        if ($self->log->is_debug) {
            $self->log->debug("The notification we're returning is " . Dumper($result));
        }
    }
}

sub get_and_parse_transactions {
    my ($self, $info) = @_;

    my $xml = $self->_load_xml_from_url(
        $self->get_transaction_query_url( $info )
    );

    my @transactions = $xml->getChildrenByTagName('transactions')->get_node(1)->getChildrenByTagName('transaction');

    return {
        current_page         => $xml->getChildrenByTagName('currentPage')->string_value,
        results_in_this_page => $xml->getChildrenByTagName('resultsInThisPage')->string_value,
        total_pages          => $xml->getChildrenByTagName('totalPages')->string_value,
        transactions         => [
            map { $self->get_transaction_details( $_ ) }
            map { $_->getChildrenByTagName('code')->string_value } @transactions
        ],
    };
}

sub get_transaction_details {
    my ($self, $code) = @_;

    my $xml = $self->_load_xml_from_url(
        $self->get_transaction_details_url( $code )
    );

    my $result = $self->_parse_transaction($xml);
    $result->{buyer_email} = $xml->getChildrenByTagName('sender')->get_node(1)->getChildrenByTagName('email')->string_value;

    return $result;
}

sub _parse_transaction {
    my ($self, $xml) = @_;

    my $date   = $xml->getChildrenByTagName('date')->string_value;
    my $ref    = $xml->getChildrenByTagName('reference')->string_value;
    my $status = $xml->getChildrenByTagName('status')->string_value;
    my $amount = $xml->getChildrenByTagName('grossAmount')->string_value;
    my $net    = $xml->getChildrenByTagName('netAmount')->string_value;
    my $fee    = $xml->getChildrenByTagName('feeAmount')->string_value;
    my $code   = $xml->getChildrenByTagName('code')->string_value;
    my $payer  = $xml->getChildrenByTagName('sender')->get_node(1)->getChildrenByTagName('name')->string_value;

    return {
        payment_id             => $ref,
        gateway_transaction_id => $code,
        status                 => $self->_interpret_status($status),
        amount                 => $amount,
        date                   => $date,
        net_amount             => $net,
        fee                    => $fee,
        exchange_rate          => 0,
        payer => {
            name => $payer,
        },
    };
}

sub _load_xml_from_url {
    my ($self, $url) = @_;

    return XML::LibXML->load_xml(
        string => LWP::Simple::get( $url )
    )->firstChild();
}

sub _build_uri {
    my ($self, $path, $info) = @_;

    $info ||= {};

    $info->{email} = $self->receiver_email;
    $info->{token} = $self->token;

    my $uri = URI->new($self->base_url . $path);

    while (my ($k, $v) = each %$info) {
        $uri->query_param($k, $v);
    }

    return $uri->as_string;
}

sub _interpret_status {
    my ($self, $status) = @_;

    $status = int($status || 0);

    # 1: aguardando pagamento
    # 2: em análise
    # 3: paga
    # 4: disponível
    # 5: em disputa
    # 6: devolvida
    # 7: cancelada

    my @status_codes = ('unknown');
    @status_codes[1,2,5] = ('processing') x 3;
    @status_codes[3,4]   = ('completed') x 2;
    $status_codes[6]     = 'refunded';
    $status_codes[7]     = 'failed';

    if ($status > 7) {
        return 'unknown';
    }

    return $status_codes[$status];
}

sub get_hidden_inputs {
    my ($self, $info) = @_;

    my $buyer = $info->{buyer};
    my $cart  = $info->{cart};

    my @hidden_inputs = (
        receiverEmail => $self->receiver_email,
        currency      => $self->currency,
        encoding      => $self->form_encoding,
        reference     => $info->{payment_id},
        senderName    => $buyer->name,
        senderEmail   => $buyer->email,
    );

    my %buyer_extra = (
        address_complement => 'shippingAddressComplement',
        address_district   => 'shippingAddressDistrict',
        address_street     => 'shippingAddressStreet',
        address_number     => 'shippingAddressNumber',
        address_city       => 'shippingAddressCity',
        address_state      => 'shippingAddressState',
        address_country    => 'shippingAddressCountry',
        address_zip_code   => 'shippingAddressPostalCode',
    );

    for (keys %buyer_extra) {
        if (my $value = $buyer->$_) {
            if ($_ eq 'shippingAddressCountry') {
                $value = uc(
                    Locale::Country::country_code2code(
                        $value, 'alpha-2', 'alpha-3'
                    )
                );
            }
            push @hidden_inputs, ( $buyer_extra{$_} => $value );
        }
    }

    my $extra_amount = 0;

    if (my $disc = $cart->discount) {
        $extra_amount -= $disc;
    }

    if (my $handl = $cart->handling) {
        $extra_amount += $handl;
    }

    if (my $tax = $cart->tax) {
        $extra_amount += $tax;
    }

    if ($extra_amount) {
        $extra_amount = sprintf( "%.2f", $extra_amount );
        push @hidden_inputs, ( extraAmount => $extra_amount );
    }

    my $i = 1;

    foreach my $item (@{ $info->{items} }) {
        push @hidden_inputs,
          (
            "itemId$i"          => $item->id,
            "itemDescription$i" => $item->description,
            "itemAmount$i"      => $item->price,
            "itemQuantity$i"    => $item->quantity,
          );

        if (my $weight = $item->weight) {
            push @hidden_inputs, ( "itemWeight$i" => $weight * 1000 ); # show in grams
        }

        if (my $ship = $item->shipping) {
            push @hidden_inputs, ( "itemShippingCost$i" => $ship );
        }

        $i++;
    }

    return @hidden_inputs;
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Business::CPI::Gateway::PagSeguro - Business::CPI's PagSeguro driver

=head1 VERSION

version 0.66

=head1 ATTRIBUTES

=head2 token

The token provided by PagSeguro

=head2 base_url

The url for PagSeguro API. Not to be confused with the checkout url, this is
just for the API.

=head1 METHODS

=head2 get_notifications_url

Reader for the notifications URL in PagSeguro's API. This uses the base_url
attribute.

=head2 get_transaction_details_url

Reader for the transaction details URL in PagSeguro's API. This uses the
base_url attribute.

=head2 get_transaction_query_url

Reader for the transaction query URL in PagSeguro's API. This uses the base_url
attribute.

=head2 get_and_parse_notification

Gets the url from L</get_notifications_url>, and loads the XML from there.
Returns a parsed standard Business::CPI hash.

=head2 get_and_parse_transactions

=head2 get_transaction_details

=head2 query_transactions

Alias for L</get_and_parse_transactions> to maintain compatibility with other
Business::CPI modules.

=head2 notify

=head2 get_hidden_inputs

=head1 SPONSORED BY

Aware - L<http://www.aware.com.br>

=head1 SEE ALSO

L<Business::CPI::Gateway::Base>

=head1 AUTHOR

André Walker <andre@andrewalker.net>

=head1 CONTRIBUTOR

Renato CRON <rentocron@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by André Walker.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
