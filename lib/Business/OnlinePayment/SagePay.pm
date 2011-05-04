package Business::OnlinePayment::SagePay;

use strict;
use Carp;
use Net::SSLeay qw(make_form post_https);
use base qw(Business::OnlinePayment);
use Devel::Dwarn;

our $VERSION = '0.13';

# CARD TYPE MAP

my %card_type = (
  'american express' => 'AMEX',
  'amex' => 'AMEX',
  'visa' => 'VISA',
  'visa electron' => 'UKE',
  'visa debit' => 'DELTA',
  'mastercard' => 'MC',
  'maestro' => 'MAESTRO',
  'international maestro' => 'MAESTRO',
  'switch' => 'MAESTRO',
  'switch solo' => 'SOLO',
  'solo' => 'SOLO',
  'diners club' => 'DINERS',
  'jcb' => 'JCB',
);

my $status = {
  TIMEOUT => 'There was a problem communicating with the payment server, please try later',
  UNKNOWN => 'There was an unknown problem taking your payment. Please try again',
  '3D_PASS' => 'Your card failed the password check.',
  2000 => 'Your card was declined by the bank.',
  5013 => 'Your card has expired.',
  3078 => 'Your e-mail was invalid.',
  4023 => 'The card issue number is invalid.',
  4024 => 'The card issue number is required.',
  2000 => 'Your card was declined by the issuer',
  2001 => 'Your card was declined by the merchant',
  5995 => 'Please ensure you have entered the correct digits off the back of your card and your billing address is correct',
  5027 => 'Card start date is invalid',
  5028 => 'Card expiry date is invalid',
  3107 => 'Please ensure you have entered your full name, not just your surname',
  3069 => 'Your card type is not supported by this vendor. Please try a different card',
  3057 => 'Your card security number was incorrect. This is normally the last 3 digits on the back of your card',
  4021 => 'Your card number was incorrect',
  5018 => "Your card security number was the incorrect length. This is normally the last 3 digits on the back of your card",
  3130 => "Your state was incorrect. Please use the standard two character state code",
  3068 => "Your card type is not supported by this vendor. Please try a different card",
  5055 => "Your postcode had incorrect characters. Please re-enter",
  3055 => "Your card was not recognised. Please try another",
};

#ACTION MAP
my %action = (
  'normal authorization' => 'PAYMENT',
  'authorization only'   => 'AUTHENTICATE',
  'post authorization'   => 'AUTHORISE',
  'refund'               => 'REFUND',
);

my %servers = (
  live => {
    url => 'live.sagepay.com',
    path => '/gateway/service/vspdirect-register.vsp',
    callback => '/gateway/service/direct3dcallback.vsp',
    authorise => '/gateway/service/authorise.vsp',
    refund => '/gateway/service/refund.vsp',
    cancel => '/gateway/service/cancel.vsp',
    token => '/gateway/service/directtoken.vsp',
    remove_token => '/gateway/service/removetoken.vsp',
    port => 443,
  },
  test => {
    url  => 'test.sagepay.com',
    path => '/gateway/service/vspdirect-register.vsp',
    callback => '/gateway/service/direct3dcallback.vsp',
    authorise => '/gateway/service/authorise.vsp',
    refund => '/gateway/service/refund.vsp',
    cancel => '/gateway/service/cancel.vsp',
    token => '/gateway/service/directtoken.vsp',
    remove_token => '/gateway/service/removetoken.vsp',
    port => 443,
  },
  simulator => {
    url => 'test.sagepay.com',
    path => '/Simulator/VSPDirectGateway.asp',
    callback => '/Simulator/VSPDirectCallback.asp',
    authorise => '/Simulator/VSPServerGateway.asp?service=VendorAuthoriseTx ',
    refund => '/Simulator/VSPServerGateway.asp?service=VendorRefundTx ',
    cancel => '/Simulator/VSPServerGateway.asp?service=VendorCancelTx',
    token => '/Simulator/VSPServerGateway.asp?Service=VendorToken',
    remove_token => '/gateway/service/removetoken.vsp',
    port => 443,
  },
  timeout => {
    url => 'localhost',
    path => '/timeout',
    callback => '/Simulator/VSPDirectCallback.asp',
    authorise => '/Simulator/VSPServerGateway.asp?service=VendorAuthoriseTx ',
    refund => '/Simulator/VSPServerGateway.asp?service=VendorRefundTx ',
    cancel => '/Simulator/VSPServerGateway.asp?service=VendorCancelTx',
    port => 3000,
  }
);

sub callback {
  my ($self, $value) = @_;
  $self->{'callback'} = $value if $value;
  return $self->{'callback'};
}

sub set_server {
  my ($self, $type) = @_;
  $self->{'_server'} = $type;
  $self->server($servers{$type}->{'url'});
  $self->path($servers{$type}->{'path'});
  $self->callback($servers{$type}->{'callback'});
  $self->port($servers{$type}->{'port'});
}

sub set_defaults {
  my $self = shift;
  $self->set_server('live');
  $self->build_subs(
    qw/protocol currency cvv2_response postcode_response error_code require_3d 
    forward_to invoice_number authentication_key pareq cross_reference callback/);
  $self->protocol('2.23');
  $self->currency('GBP');
  $self->require_3d(0);
}

sub do_remap {
  my ($self, $content, %map) = @_;
  my %remapped = ();
  while (my ($k, $v) = each %map) {
    no strict 'refs';
    $remapped{$k} = ref( $map{$k} ) ? 
      ${ $map{$k} }
      :
      $content->{$v};
  }
  return %remapped;
}

sub format_amount {
  my $amount = shift;
  return sprintf("%.2f",$amount);
}

sub submit_3d {
  my $self = shift;
  my %content = $self->content;
  my %post_data = (
    ( map { $_ => $content{$_} } qw(login password) ),
    MD    => $content{'cross_reference'},
    PaRes => $content{'pares'},
  );
  $self->set_server($ENV{'SAGEPAY_F_SIMULATOR'} ? 'simulator' : 'test') 
    if $self->test_transaction;
  my ($page, $response, %headers) = 
    post_https(
      $self->server,
      $self->port,
      $self->callback,
      undef,
      make_form(%post_data)
    );
  unless ($page) {
    $self->error_message($status->{TIMEOUT});
    return;
  }

  my $rf = $self->_parse_response($page);

  if($ENV{'SAGEPAY_DEBUG'}) {
    warn "3DSecure:";
    Dwarn $rf;
  }

  $self->server_response($rf);
  $self->result_code($rf->{'Status'});
  $self->authentication_key($rf->{'SecurityKey'});
  $self->authorization($rf->{'VPSTxId'});

  unless(
    $self->is_success($rf->{'Status'} eq 'OK'
    || $rf->{'Status'} eq 'AUTHENTICATED' 
    ?  1 : 0)) {
    $self->error_message($status->{'3D_PASS'});
    if($ENV{'SAGEPAY_DEBUG_ERROR_ONLY'}) {
      Dwarn $rf;
    }
    return 0;
  } else{
    return 1;
  }
}


sub void_action { #void authorization
  my $self = shift;
  $self->initialise;
  my %content = $self->content();
  my %field_mapping = (
    VpsProtocol   => \($self->protocol),
    Vendor        => \($self->vendor),
    VendorTxCode  => 'invoice_number',
    VPSTxId       => 'authentication_id',
    SecurityKey   => 'authentication_key',
    TxAuthNo      => ''
  );
  my %post_data = $self->do_remap(\%content,%field_mapping);
  $post_data{'TxType'} = 'VOID';

  if($ENV{'SAGEPAY_DEBUG'}) {
    Dwarn %post_data;
  }

  $self->path($servers{$self->{'_server'}}->{'cancel'});
  my ($page, $response, %headers) = 
    post_https(
      $self->server,
      $self->port,
      $self->path,
      undef,
      make_form(
        %post_data
      )
    );
  unless ($page) {
    $self->error_message($status->{TIMEOUT});
    $self->is_success(0);
    return;
  }

  my $rf = $self->_parse_response($page);

  if($ENV{'SAGEPAY_DEBUG'}) {
    warn "Cancellation:";
    Dwarn $rf;
  }

  $self->server_response($rf);
  $self->result_code($rf->{'Status'});
  unless($self->is_success($rf->{'Status'} eq 'OK'? 1 : 0)) {
    if($ENV{'SAGEPAY_DEBUG_ERROR_ONLY'}) {
      Dwarn $rf;
    }
    $self->error_message($rf->{'StatusDetail'});
  }  
}

sub cancel_action { #cancel authentication
  my $self = shift;
  $self->initialise;
  my %content = $self->content();
  my %field_mapping = (
    VpsProtocol   => \($self->protocol),
    Vendor        => \($self->vendor),
    VendorTxCode  => 'parent_invoice_number',
    TxAuthNo      => 'invoice_number',
    VPSTxId       => 'authentication_id',
    SecurityKey   => 'authentication_key',
  );
  my %post_data = $self->do_remap(\%content,%field_mapping);
  $post_data{'TxType'} = 'CANCEL';

  if($ENV{'SAGEPAY_DEBUG'}) {
    Dwarn %post_data;
  }

  $self->path($servers{$self->{'_server'}}->{'cancel'});
  my ($page, $response, %headers) = 
    post_https(
      $self->server,
      $self->port,
      $self->path,
      undef,
      make_form(
        %post_data
      )
    );
  unless ($page) {
    $self->error_message($status->{TIMEOUT});
    $self->is_success(0);
    return;
  }

  my $rf = $self->_parse_response($page);

  if($ENV{'SAGEPAY_DEBUG'}) {
    warn "Cancellation:";
    Dwarn $rf;
  }

  $self->server_response($rf);
  $self->result_code($rf->{'Status'});
  unless($self->is_success($rf->{'Status'} eq 'OK'? 1 : 0)) {
    if($ENV{'SAGEPAY_DEBUG_ERROR_ONLY'}) {
      Dwarn $rf;
    }
    $self->error_message($rf->{'StatusDetail'});
  }  
}

sub initialise {
  my $self = shift;
  croak "Need vendor ID"
    unless defined $self->vendor;
  $self->set_server($ENV{'SAGEPAY_F_SIMULATOR'} ? 'simulator' : 'test') 
    if $self->test_transaction;
}

sub auth_action { 
  my ($self, $action) = @_;
  $self->initialise;
  
  my %content = $self->content();
  my %field_mapping = (
    VpsProtocol => \($self->protocol),
    Vendor      => \($self->vendor),
    TxType      => \($action{lc $content{'action'}}),
    VendorTxCode=> 'invoice_number',
    Description => 'description',
    Currency  => \($self->currency),
    Amount      => \(format_amount($content{'amount'})),
    RelatedVPSTxId => 'parent_auth',
    RelatedVendorTxCode => 'parent_invoice_number',
    RelatedSecurityKey => 'authentication_key',
  );
  my %post_data = $self->do_remap(\%content,%field_mapping);

  if($ENV{'SAGEPAY_DEBUG'}) {
    Dwarn %post_data;
  }

  $self->path($servers{$self->{'_server'}}->{lc $post_data{'TxType'}});
  my ($page, $response, %headers) = 
    post_https(
      $self->server,
      $self->port,
      $self->path,
      undef,
      make_form(
        %post_data
      )
    );
  unless ($page) {
    $self->error_message($status->{TIMEOUT});
    $self->is_success(0);
    return;
  }

  my $rf = $self->_parse_response($page);

  if($ENV{'SAGEPAY_DEBUG'}) {
    warn "Authorization:";
    Dwarn $rf;
  }

  $self->server_response($rf);
  $self->result_code($rf->{'Status'});
  $self->authorization($rf->{'VPSTxId'});
  unless($self->is_success($rf->{'Status'} eq 'OK'? 1 : 0)) {
    if($ENV{'SAGEPAY_DEBUG_ERROR_ONLY'}) {
      Dwarn $rf;
    }
    my $code = substr $rf->{'StatusDetail'}, 0 ,4;
    $self->error_code($code);
    $self->error_message($status->{$code} || $status->{UNKNOWN});
  }

}

sub sanitised_content {
  my ($self,$content) = @_;
  my %content = $self->content();
  $content{'expiration'} =~ s#/##g;
  $content{'startdate'} =~ s#/##g if $content{'startdate'};

  $content{'card_name'} = 
       $content{'name_on_card'} 
    || $content{'first_name'} . ' ' . ($content{'last_name'}||"");
  $content{'customer_name'} = 
       $content{'customer_name'}
    || $content{'first_name'} ? 
          $content{'first_name'} . ' ' . $content{'last_name'} : undef;
  # new protocol requires first and last name - do some people even have both!?
  $content{'last_name'} ||= $content{'first_name'}; 
  $content{'action'} = lc $content{'action'};
  $content{'card_type'} = $card_type{lc $content{'type'}};
  $content{'amount'} = format_amount($content{'amount'})
    if $content{'amount'};
  
  return \%content;
}

sub post_request {
  my ($self,$type,$data) = @_;
  
  $self->path($servers{$self->{'_server'}}->{$type});
  
  if($ENV{'SAGEPAY_DEBUG'}) {
    warn sprintf("Posting to %s:%s%s",
      $self->server, $self->port, $self->path);
    Dwarn $data;
  }
  
  my ($page, $response, %headers) = post_https(
    $self->server,
    $self->port,
    $self->path,
    undef,
    make_form( %$data )
  );
  
  unless ($page) {
    $self->error_message($status->{TIMEOUT});
    $self->is_success(0);
    return;
  }

  my $rf = $self->_parse_response($page);
  $self->server_response($rf);
  $self->result_code($rf->{'Status'});
  $self->authorization($rf->{'VPSTxId'});
  $self->authentication_key($rf->{'SecurityKey'});
}

sub token_action { #get token from card details
  my $self = shift;
  $self->initialise;
  my %field_mapping = (
    VpsProtocol => \($self->protocol),
    Vendor      => \($self->vendor),
    TxType      => \('TOKEN'),
    CardHolder  => 'card_name',
    CardNumber  => 'card_number',
    StartDate => 'startdate',
    ExpiryDate  => 'expiration',
    IssueNumber => 'issue_number',
    CV2         => 'cvv2',
    CardType  => 'card_type',
    Currency    => \($self->currency),
  );
  $self->post_request('token',{
    $self->do_remap(
      $self->sanitised_content,
      %field_mapping
    )
  });
}

sub token_submit { #submit a payment with token
  my $self = shift;
  $self->initialise;
  my %field_mapping = (
    VpsProtocol => \($self->protocol),
    Vendor      => \($self->vendor),
    TxType      => \('PAYMENT'),
    CardHolder  => 'card_name',
    CardNumber  => 'card_number',
    StartDate => 'startdate',
    ExpiryDate  => 'expiration',
    IssueNumber => 'issue_number',
    CV2         => 'cvv2',
    CardType  => 'card_type',
    Currency    => \($self->currency),
  );
  $self->post_request('token',{
    $self->do_remap(
      $self->sanitised_content,
      %field_mapping
    )
  });
  
}

sub submit {
  my $self = shift;
  $self->initialise;
  my %content = $self->sanitised_content;
  
  my %field_mapping = (
    VpsProtocol => \($self->protocol),
    Vendor      => \($self->vendor),
    TxType      => 'action',
    VendorTxCode=> 'invoice_number',
    Description => 'description',
    Currency    => \($self->currency),
    CardHolder  => 'card_name',
    CardNumber  => 'card_number',
    CV2         => 'cvv2',
    ExpiryDate  => 'expiration',
    StartDate => 'startdate',
    Amount      => 'amount',
    IssueNumber => 'issue_number',
    CardType  => 'card_type',
    ApplyAVSCV2 => 0,
    BillingSurname  => 'last_name',
    BillingFirstnames  => 'first_name',
    BillingAddress1  => 'address',
    BillingPostCode => 'zip',
    BillingCity => 'city',
    BillingState => 'state',
    BillingCountry => 'country',

    DeliverySurname  => 'last_name',
    DeliveryFirstnames  => 'first_name',
    DeliveryAddress1  => 'address',
    DeliveryPostCode => 'zip',
    DeliveryCity => 'city',
    DeliveryCountry => 'country',
    DeliveryState => 'state',

    CustomerName    => 'customer_name',
    ContactNumber   => 'telephone',
    ContactFax    => 'fax',
    CustomerEmail => 'email',
  );

  my %post_data = $self->do_remap(\%content,%field_mapping);

  if($ENV{'SAGEPAY_DEBUG'}) {
    warn "Authentication Form:";
    Dwarn {
      %post_data, 
      CV2 => "XXX", 
      CardNumber => "XXXX XXXX XXXX XXXX"
    };
  }

  $self->path($servers{$self->{'_server'}}->{'authorise'}) 
    if $post_data{'TxType'} eq 'AUTHORISE';
  my ($page, $response, %headers) = post_https(
    $self->server,
    $self->port,
    $self->path,
    undef,
    make_form(
      %post_data
    )
  );
  unless ($page) {
    $self->error_message($status->{TIMEOUT});
    $self->is_success(0);
    return;
  }

  my $rf = $self->_parse_response($page);
  $self->server_response($rf);
  $self->result_code($rf->{'Status'});
  $self->authorization($rf->{'VPSTxId'});
  $self->authentication_key($rf->{'SecurityKey'});

  if($self->result_code eq '3DAUTH' && $rf->{'3DSecureStatus'} eq 'OK') {
    $self->require_3d(1);
    $self->forward_to($rf->{'ACSURL'});
    $self->pareq($rf->{'PAReq'});
    $self->cross_reference($rf->{'MD'});
  }
  $self->cvv2_response($rf->{'CV2Result'});
  $self->postcode_response($rf->{'PostCodeResult'});
  if($ENV{'SAGEPAY_DEBUG'}) {
    warn "Authentication Response:";
    Dwarn $rf;
  }
  unless($self->is_success(
    $rf->{'Status'} eq '3DAUTH' ||
    $rf->{'Status'} eq 'OK' ||
    $rf->{'Status'} eq 'AUTHENTICATED' ||
    $rf->{'Status'} eq 'REGISTERED' 
    ? 1 : 0)) {
      my $code = substr $rf->{'StatusDetail'}, 0 ,4;
      if($ENV{'SAGEPAY_DEBUG_ERROR_ONLY'}) {
        Dwarn $rf;
      }
      $self->error_code($code);
      $self->error_message($status->{$code} || $status->{UNKNOWN});
    }
}

sub _parse_response {
  my ($self,$response) = @_;
  my $crlfpattern = qq{[\015\012\n\r]};
  my %values = map { split(/=/,$_, 2) } grep(/=.+$/,split (/$crlfpattern/,$response));
  return \%values;
}

=head1 NAME

Business::OnlinePayment::SagePay - SagePay backend for Business::OnlinePayment

=head1 SYNOPSIS

  use Business::OnlinePayment;

  my $tx = Business::OnlinePayment->new(
      "SagePay",
      "username"  => "abc",
  );

  $tx->content(
      type           => 'VISA',
      login          => 'testdrive',
      password       => '',
      action         => 'Normal Authorization',
      description    => 'Business::OnlinePayment test',
      amount         => '49.95',
      invoice_number => '100100',
      customer_id    => 'jsk',
      first_name     => 'Jason',
      last_name      => 'Kohles',
      address        => '123 Anystreet',
      city           => 'Anywhere',
      state          => 'UT',
      zip            => '84058',
      card_number    => '4007000000027',
      expiration     => '09/02',
      cvv2           => '1234', #optional
      referer        => 'http://valid.referer.url/',
  );

  $tx->set_server('simulator'); #live, simulator or test(default)

  $tx->submit();

   if ($tx->is_success) {
       print "Card processed successfully: " . $tx->authorization . "\n";
   } else {
       print "Card was rejected: " . $tx->error_message . "\n";
   }

=cut

=head1 DESCRIPTION

This perl module provides integration with the SagePay VSP payments system.

=head1 BUGS

Please report any bugs or feature requests to C<bug-business-onlinepayment-sagepay at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Business-OnlinePayment-SagePay>.  I will be notified, and then you'll automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Business::OnlinePayment::SagePay

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Business-OnlinePayment-SagePay>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Business-OnlinePayment-SagePay>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Business-OnlinePayment-SagePay>

=item * Search CPAN

L<http://search.cpan.org/dist/Business-OnlinePayment-SagePay>

=back

=head1 SEE ALSO

L<Business::OnlinePayment>

=head1 AUTHOR

  purge: Simon Elliott <cpan@browsing.co.uk>

=head1 ACKNOWLEDGEMENTS

  To Airspace Software Ltd <http://www.airspace.co.uk>, for the sponsorship.

  To Wallace Reis, for comments and patches.

=head1 LICENSE

  This library is free software under the same license as perl itself.

=cut

1;