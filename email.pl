#!/usr/bin/perl


use Date::Calc qw(Today_and_Now);
use File::Copy;
use File::Basename;
use DBI;
use Mail::Sendmail;
use Net::SMTP;
use Net::SMTP::SSL;
use Authen::SASL;
require MIME::Base64;

use Email::Sender::Simple qw(sendmail);
use Email::Sender::Transport::SMTPS;
use Email::Simple ();
use Email::Simple::Creator ();

my $smtpserver = 'mail.7r.com.au';
#my $smtpserver = 'ub007lcs13.cbr.the-server.net.au';
my $smtpport = 465;
my $smtpuser   = 'shares@7r.com.au';
my $smtppassword = 'D3l3t312';
my $mailfrom = "shares\@7r.com.au";
my $mailto = "sstrijak\@7r.com.au";

($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
$starttime = "$year-$month-$day-$hour:$min:$sec";
my $subject = "Data loaded on $starttime";
my $message = "Test.\r\n";

my $sasl;
my $mechanisms =  ['AUTH', 500];

my $smtp = Net::SMTP::SSL->new($smtpserver, Port=>$smtpport, Timeout => 10, Debug => 1);

$smtp->auth($smtpuser,$smtppassword);
$smtp->mail($mailfrom);
$smtp->to($mailto);
$smtp->recipient($mailto);
$smtp->data();
$smtp->datasend("To: $mailto\n");
$smtp->datasend("From: $mailfrom\n");
$smtp->datasend("Subject: $subject\n");
$smtp->datasend("\n"); # done with header
$smtp->datasend($message);
#smtp->data($message);
$smtp->dataend();
$smtp->quit(); # all done. message sent.

	logentry ( "Mail sent OK." );
	logentry ( "Error sending mail: ".$Mail::Sendmail::error );
	logentry ( "\$Mail::Sendmail::log says: ".$Mail::Sendmail::log );

close LOG;



sub logentry () {
	my $entry = $_[0];
	print STDOUT "$entry\n";
	($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
	$now = "$year-$month-$day-$hour:$min:$sec";
	print LOG $now; 
	print LOG ": $entry\n"; 
}

