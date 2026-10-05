import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../api/music_api.dart';

const Set<String> knownDisposableDomains = {
  '10minutemail.com', '10minutemail.net', '10minmail.com', '20minutemail.com', 'tempmail.com',
  'temp-mail.org', 'temp-mail.io', 'tempmail.net', 'tempail.com', 'mailinator.com',
  'guerrillamail.com', 'guerrillamail.net', 'guerrillamail.biz', 'guerrillamail.org', 'sharklasers.com',
  'grr.la', 'guerrillamailblock.com', 'pokemail.net', 'spam4.me', 'trashmail.com',
  'trashmail.net', 'trashmail.org', 'trashmail.me', 'yopmail.com', 'yopmail.net',
  'yopmail.fr', 'cool.fr.nf', 'jetable.fr.nf', 'nospam.ze.tc', 'nomail.xl.cx',
  'dispostable.com', 'getairmail.com', 'throwawaymail.com', 'fakemailgenerator.com', 'maildrop.cc',
  'inboxkitten.com', 'generator.email', 'emailondeck.com', 'crazymailing.com', 'mohmal.com',
  'burnermail.io', 'nada.ltd', 'getnada.com', 'abcvg.com', 'dropmail.me',
  'tempinbox.com', 'tmail.ws', 'chacuo.net', '027168.com', 'fakeinbox.com',
  'mytemp.email', 'harakirimail.com', 'mailcatch.com', 'mintemail.com', 'spambog.com',
  'tempinbox.xyz', 'disposablemail.com', 'throwawayemail.com', 'armyspy.com', 'cuvox.de',
  'dayrep.com', 'fleckens.hu', 'gustr.com', 'jourrapide.com', 'rhyta.com',
  'superrito.com', 'teleworm.us', 'einrot.com', 'mytempemail.com', 'spambox.us',
  'spamevader.com', 'kasmail.com', 'maildu.de', 'mailnull.com', 'mailscrap.com',
  'incognitomail.com', 'anonbox.net', 'anonymbox.com', 'bouncr.com', 'curryjunk.com',
  'deadaddress.com', 'despam.it', 'dontreg.com', 'dumpemail.com', 'easytrashmail.com',
  'emailtemporaneo.net', 'fakeinformation.com', 'filzmail.com', 'forwardcat.com', 'gishpuppy.com',
  'greensloth.com', 'h8s.org', 'haltospam.com', 'hidemail.de', 'hidemyass.com',
  'hotpop.com', 'hulapla.de', 'ieatspam.com', 'instant-mail.de', 'ipoo.org',
  'jetable.org', 'junkmail.com', 'klzlk.com', 'kurzepost.de', 'link2mail.net',
  'lookugly.com', 'lortemail.dk', 'madhackers.biz', 'mail2rss.org', 'mail4trash.com',
  'mailbidon.com', 'maileater.com', 'mailexpire.com', 'mailforspam.com', 'mailfreeonline.com',
  'mailimate.com', 'mailin8r.com', 'mailme.ir', 'mailmetrash.com', 'mailmoat.com',
  'mailnesia.com', 'mailquack.com', 'mailslap.com', 'mailtothis.com', 'mailtrash.net',
  'makemeadress.com', 'meltmail.com', 'messagebeamer.de', 'misterpinball.de', 'moncourrier.fr.nf',
  'monemail.fr.nf', 'monmail.fr.nf', 'mt2009.com', 'mycleaninbox.net', 'mytrashmail.com',
  'nepwk.com', 'netcourrier.com', 'noclickemail.com', 'nomail.sk', 'nospam4.us',
  'nospamfor.us', 'nospammail.net', 'notsharingmy.info', 'nowmymail.com', 'objectmail.com',
  'oneoffmail.com', 'onewaymail.com', 'otherinbox.com', 'ourproject.org', 'pookmail.com',
  'postacin.com', 'privacy.net', 'privatdemail.net', 'proxymail.eu', 'pubmail.com',
  'qip.ru', 'quickmail.info', 'rcpt.at', 'recursor.net', 'regbypass.com',
  'rmqkr.net', 'safetymail.info', 'sendspamhere.com', 'shieldemail.com', 'shiftmail.com',
  'shortmail.net', 'sify.com', 'skeptiks.com', 'slopsbox.com', 'smashmail.de',
  'sofort-mail.de', 'sogetthis.com', 'soodonims.com', 'spamavert.com', 'spambob.com',
  'spamcannon.com', 'spamcon.org', 'spamcorptastic.com', 'spamcowboy.com', 'spamday.com',
  'spamex.com', 'spamfree24.org', 'spamgourmet.com', 'spamhole.com', 'spaml.com',
  'spammotel.com', 'spamoff.de', 'spampal.org', 'spamprefix.com', 'spamsource.com',
  'spamspot.com', 'spamstop.net', 'spamtrap.ro', 'speedpost.net', 'superstachel.de',
  'suremail.info', 'tafmail.com', 'teewars.org', 'tempemail.net', 'temporaryemail.net',
  'temporaryinbox.com', 'thankyou2010.com', 'thisisnotmyrealemail.com', 'throwawayemailaddress.com',
  'tradermail.info', 'trash-mail.com', 'trash-me.com', 'trashcanmail.com', 'trashmailer.com',
  'trashymail.com', 'tvhost.org', 'uroid.com', 'veryrealemail.com', 'vidavee.com',
  'warimpex.at', 'wegwerfadresse.de', 'wegwerfemail.de', 'wegwerfmail.de', 'wegwerfmail.net',
  'whyspam.me', 'willselfdestruct.com', 'wrongmail.com', 'wuzupmail.net', 'xagloo.com',
  'xemaps.com', 'xents.com', 'xmaily.com', 'yapped.net', 'yehey.com',
  'yep.it', 'yogamaven.com', 'yomail.info', 'zippymail.info', 'zoemail.org',
  'zxcvbnm.co.uk', 'zzrgg.com'
};

final RegExp disposableKeywordPattern = RegExp(
  r'(^|\.)(temp|dispos|trash|fake|throwaway|burner|guerrilla|mailinator|10minute|maildrop|generator|spambox|fakemail|yopmail|mohmal|discard|sharklaser|mytemp|jetable)[\w-]*\.[a-z]{2,}$',
  caseSensitive: false,
);

class DisposableEmailCheck {
  final bool isDisposable;
  final String? message;
  const DisposableEmailCheck({required this.isDisposable, this.message});
}

DisposableEmailCheck checkLocalDisposableEmail(String email) {
  if (!email.contains('@')) {
    return const DisposableEmailCheck(isDisposable: true, message: 'Please enter a valid email address.');
  }

  final parts = email.trim().toLowerCase().split('@');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
    return const DisposableEmailCheck(isDisposable: true, message: 'Please enter a valid email address.');
  }

  final domain = parts[1].trim();

  // 1. Direct domain lookup
  if (knownDisposableDomains.contains(domain)) {
    return DisposableEmailCheck(
      isDisposable: true,
      message: "The email provider '$domain' is a disposable/temporary service. Please use a valid personal email (e.g. Gmail, Outlook, Yahoo, iCloud).",
    );
  }

  // 2. Parent domain lookup (e.g. sub.tempmail.com)
  final segments = domain.split('.');
  if (segments.length > 2) {
    final parent = segments.sublist(segments.length - 2).join('.');
    if (knownDisposableDomains.contains(parent)) {
      return DisposableEmailCheck(
        isDisposable: true,
        message: "The email provider '$domain' is a disposable/temporary service. Please use a valid personal email.",
      );
    }
  }

  // 3. Keyword pattern lookup
  if (disposableKeywordPattern.hasMatch(domain)) {
    return DisposableEmailCheck(
      isDisposable: true,
      message: "The domain '$domain' appears to be a disposable or temporary email service. Please use a trusted provider.",
    );
  }

  return const DisposableEmailCheck(isDisposable: false);
}

Future<DisposableEmailCheck> validateEmailNotDisposable(String email) async {
  // Fast tier 1 local check
  final local = checkLocalDisposableEmail(email);
  if (local.isDisposable) return local;

  // Tier 2 backend validation against eramitgupta/disposable-email 110k+ list
  try {
    final uri = Uri.parse('${MusicApi.defaultBaseUrl}/api/auth/validate-email').replace(
      queryParameters: {'email': email.trim().toLowerCase()},
    );
    final response = await http.get(uri).timeout(const Duration(milliseconds: 2500));
    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (data['disposable'] == true) {
        return DisposableEmailCheck(
          isDisposable: true,
          message: data['message']?.toString() ?? 'Disposable or temporary email addresses are not allowed. Please use a personal email.',
        );
      }
    }
  } catch (_) {
    // If backend times out or network issue, fallback to clean local check
  }

  return const DisposableEmailCheck(isDisposable: false);
}
