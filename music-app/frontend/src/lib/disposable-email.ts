import { API_URL } from "./api";

// Fast embedded lookup of top disposable and temporary email domains
export const KNOWN_DISPOSABLE_DOMAINS = new Set<string>([
  "10minutemail.com", "10minutemail.net", "10minmail.com", "20minutemail.com", "tempmail.com",
  "temp-mail.org", "temp-mail.io", "tempmail.net", "tempail.com", "mailinator.com",
  "guerrillamail.com", "guerrillamail.net", "guerrillamail.biz", "guerrillamail.org", "sharklasers.com",
  "grr.la", "guerrillamailblock.com", "pokemail.net", "spam4.me", "trashmail.com",
  "trashmail.net", "trashmail.org", "trashmail.me", "yopmail.com", "yopmail.net",
  "yopmail.fr", "cool.fr.nf", "jetable.fr.nf", "nospam.ze.tc", "nomail.xl.cx",
  "dispostable.com", "getairmail.com", "throwawaymail.com", "fakemailgenerator.com", "maildrop.cc",
  "inboxkitten.com", "generator.email", "emailondeck.com", "crazymailing.com", "mohmal.com",
  "burnermail.io", "nada.ltd", "getnada.com", "abcvg.com", "dropmail.me",
  "tempinbox.com", "tmail.ws", "chacuo.net", "027168.com", "fakeinbox.com",
  "mytemp.email", "harakirimail.com", "mailcatch.com", "mintemail.com", "spambog.com",
  "tempinbox.xyz", "disposablemail.com", "throwawayemail.com", "armyspy.com", "cuvox.de",
  "dayrep.com", "fleckens.hu", "gustr.com", "jourrapide.com", "rhyta.com",
  "superrito.com", "teleworm.us", "einrot.com", "mytempemail.com", "spambox.us",
  "spamevader.com", "kasmail.com", "maildu.de", "mailnull.com", "mailscrap.com",
  "incognitomail.com", "anonbox.net", "anonymbox.com", "bouncr.com", "curryjunk.com",
  "deadaddress.com", "despam.it", "dontreg.com", "dumpemail.com", "easytrashmail.com",
  "emailtemporaneo.net", "fakeinformation.com", "filzmail.com", "forwardcat.com", "gishpuppy.com",
  "greensloth.com", "h8s.org", "haltospam.com", "hidemail.de", "hidemyass.com",
  "hotpop.com", "hulapla.de", "ieatspam.com", "instant-mail.de", "ipoo.org",
  "jetable.org", "junkmail.com", "klzlk.com", "kurzepost.de", "link2mail.net",
  "lookugly.com", "lortemail.dk", "madhackers.biz", "mail2rss.org", "mail4trash.com",
  "mailbidon.com", "maileater.com", "mailexpire.com", "mailforspam.com", "mailfreeonline.com",
  "mailimate.com", "mailin8r.com", "mailme.ir", "mailmetrash.com", "mailmoat.com",
  "mailnesia.com", "mailquack.com", "mailslap.com", "mailtothis.com", "mailtrash.net",
  "makemeadress.com", "meltmail.com", "messagebeamer.de", "misterpinball.de", "moncourrier.fr.nf",
  "monemail.fr.nf", "monmail.fr.nf", "mt2009.com", "mycleaninbox.net", "mytrashmail.com",
  "nepwk.com", "netcourrier.com", "noclickemail.com", "nomail.sk", "nospam4.us",
  "nospamfor.us", "nospammail.net", "notsharingmy.info", "nowmymail.com", "objectmail.com",
  "oneoffmail.com", "onewaymail.com", "otherinbox.com", "ourproject.org", "pookmail.com",
  "postacin.com", "privacy.net", "privatdemail.net", "proxymail.eu", "pubmail.com",
  "qip.ru", "quickmail.info", "rcpt.at", "recursor.net", "regbypass.com",
  "rmqkr.net", "safetymail.info", "sendspamhere.com", "shieldemail.com", "shiftmail.com",
  "shortmail.net", "sify.com", "skeptiks.com", "slopsbox.com", "smashmail.de",
  "sofort-mail.de", "sogetthis.com", "soodonims.com", "spamavert.com", "spambob.com",
  "spamcannon.com", "spamcon.org", "spamcorptastic.com", "spamcowboy.com", "spamday.com",
  "spamex.com", "spamfree24.org", "spamgourmet.com", "spamhole.com", "spaml.com",
  "spammotel.com", "spamoff.de", "spampal.org", "spamprefix.com", "spamsource.com",
  "spamspot.com", "spamstop.net", "spamtrap.ro", "speedpost.net", "superstachel.de",
  "suremail.info", "tafmail.com", "teewars.org", "tempemail.net", "temporaryemail.net",
  "temporaryinbox.com", "thankyou2010.com", "thisisnotmyrealemail.com", "throwawayemailaddress.com",
  "tradermail.info", "trash-mail.com", "trash-me.com", "trashcanmail.com", "trashmailer.com",
  "trashymail.com", "tvhost.org", "uroid.com", "veryrealemail.com", "vidavee.com",
  "warimpex.at", "wegwerfadresse.de", "wegwerfemail.de", "wegwerfmail.de", "wegwerfmail.net",
  "whyspam.me", "willselfdestruct.com", "wrongmail.com", "wuzupmail.net", "xagloo.com",
  "xemaps.com", "xents.com", "xmaily.com", "yapped.net", "yehey.com",
  "yep.it", "yogamaven.com", "yomail.info", "zippymail.info", "zoemail.org",
  "zxcvbnm.co.uk", "zzrgg.com"
]);

// Pattern matcher for throwaway keywords embedded in domain names
const DISPOSABLE_PATTERN = /(^|\.)(temp|dispos|trash|fake|throwaway|burner|guerrilla|mailinator|10minute|maildrop|generator|spambox|fakemail|yopmail|mohmal|discard|sharklaser|mytemp|jetable)[\w-]*\.[a-z]{2,}$/i;

export function isLocalDisposableEmail(email: string): { disposable: boolean; reason?: string } {
  if (!email || !email.includes("@")) {
    return { disposable: true, reason: "Please enter a valid email address." };
  }

  const parts = email.trim().toLowerCase().split("@");
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    return { disposable: true, reason: "Please enter a valid email address." };
  }

  const domain = parts[1].trim();

  // 1. Check direct domain in blocklist
  if (KNOWN_DISPOSABLE_DOMAINS.has(domain)) {
    return {
      disposable: true,
      reason: `The email provider '${domain}' is a disposable/temporary service. Please use a valid personal email (e.g. Gmail, Outlook, Yahoo, iCloud).`,
    };
  }

  // 2. Check parent domain (e.g. sub.tempmail.com)
  const segments = domain.split(".");
  if (segments.length > 2) {
    const parentDomain = segments.slice(-2).join(".");
    if (KNOWN_DISPOSABLE_DOMAINS.has(parentDomain)) {
      return {
        disposable: true,
        reason: `The email provider '${domain}' is a disposable/temporary service. Please use a valid personal email.`,
      };
    }
  }

  // 3. Check suspicious keywords pattern
  if (DISPOSABLE_PATTERN.test(domain)) {
    return {
      disposable: true,
      reason: `The email domain '${domain}' appears to be a temporary or disposable service. Please use a trusted email provider.`,
    };
  }

  return { disposable: false };
}

/**
 * Validates whether an email is not disposable.
 * Combines fast client-side check + full 110k+ repository check via backend.
 */
export async function validateEmailNotDisposable(email: string): Promise<{ valid: boolean; error?: string }> {
  // Tier 1: Fast local check
  const localCheck = isLocalDisposableEmail(email);
  if (localCheck.disposable) {
    return { valid: false, error: localCheck.reason };
  }

  // Tier 2: Query backend (backed by eramitgupta/disposable-email 110k+ list)
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 2500);

    const res = await fetch(
      `${API_URL}/api/auth/validate-email?email=${encodeURIComponent(email.trim().toLowerCase())}`,
      { signal: controller.signal, cache: "no-store" }
    );
    clearTimeout(timeout);

    if (res.ok) {
      const data = await res.json();
      if (data.disposable) {
        return {
          valid: false,
          error: data.message || "Disposable or temporary email addresses are not allowed. Please use a personal email.",
        };
      }
    }
  } catch {
    // If backend is unreachable or times out, local validation already passed
  }

  return { valid: true };
}
