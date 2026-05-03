<?php
/**
 * Plugin Name: Volcán — Mailpit redirect
 * Description: Routes every wp_mail() call to the local Mailpit SMTP service so
 *              outgoing email is captured instead of delivered.
 * Version:     1.0.0
 * Author:      Volcán Migration (dev environment)
 *
 * @package VolcanMigration\Dev
 */

defined( 'ABSPATH' ) || exit;

add_action(
	'phpmailer_init',
	static function ( $phpmailer ) {
		$phpmailer->isSMTP();
		$phpmailer->Host        = 'mailpit';
		$phpmailer->Port        = 1025;
		$phpmailer->SMTPAuth    = false;
		$phpmailer->SMTPAutoTLS = false;
		$phpmailer->SMTPSecure  = '';
		$phpmailer->From        = 'wordpress@volcan.localhost';
		$phpmailer->FromName    = 'Volcán Dev';
	}
);
