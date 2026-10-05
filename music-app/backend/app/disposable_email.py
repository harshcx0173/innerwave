from __future__ import annotations

import os
import re
import threading
import time
from urllib.error import URLError
from urllib.request import Request, urlopen

DISPOSABLE_EMAIL_RAW_URL = "https://raw.githubusercontent.com/eramitgupta/disposable-email/main/disposable_email.txt"
CACHE_FILE_PATH = os.path.join(os.path.dirname(__file__), "disposable_email_domains.txt")
CACHE_TTL_SECONDS = 86400  # 24 hours

# Pre-seeded top disposable and temporary email domains for instant zero-latency protection
PRESEEDED_DOMAINS: set[str] = {
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
    "jetable.org", "junkmail.com", "kasmail.com", "klzlk.com", "kurzepost.de",
    "link2mail.net", "lookugly.com", "lortemail.dk", "madhackers.biz", "mail2rss.org",
    "mail4trash.com", "mailbidon.com", "maileater.com", "mailexpire.com", "mailforspam.com",
    "mailfreeonline.com", "mailimate.com", "mailin8r.com", "mailme.ir", "mailmetrash.com",
    "mailmoat.com", "mailnesia.com", "mailnull.com", "mailquack.com", "mailslap.com",
    "mailtothis.com", "mailtrash.net", "makemeadress.com", "meltmail.com", "messagebeamer.de",
    "misterpinball.de", "moncourrier.fr.nf", "monemail.fr.nf", "monmail.fr.nf", "mt2009.com",
    "mycleaninbox.net", "mytrashmail.com", "nepwk.com", "netcourrier.com", "noclickemail.com",
    "nomail.sk", "nospam4.us", "nospamfor.us", "nospammail.net", "notsharingmy.info",
    "nowmymail.com", "objectmail.com", "oneoffmail.com", "onewaymail.com", "otherinbox.com",
    "ourproject.org", "pookmail.com", "postacin.com", "privacy.net", "privatdemail.net",
    "proxymail.eu", "pubmail.com", "qip.ru", "quickmail.info", "rcpt.at",
    "recursor.net", "regbypass.com", "rmqkr.net", "safetymail.info", "sendspamhere.com",
    "sharklasers.com", "shieldemail.com", "shiftmail.com", "shortmail.net", "sify.com",
    "skeptiks.com", "slopsbox.com", "smashmail.de", "sofort-mail.de", "sogetthis.com",
    "soodonims.com", "spamavert.com", "spambob.com", "spambob.net", "spambob.org",
    "spambox.us", "spamcannon.com", "spamcannon.net", "spamcon.org", "spamcorptastic.com",
    "spamcowboy.com", "spamcowboy.net", "spamcowboy.org", "spamday.com", "spamex.com",
    "spamfree24.org", "spamgourmet.com", "spamgourmet.net", "spamgourmet.org", "spamhole.com",
    "spaml.com", "spaml.de", "spammotel.com", "spamoff.de", "spampal.org",
    "spamprefix.com", "spamsource.com", "spamspot.com", "spamstop.net", "spamtrap.ro",
    "speedpost.net", "superstachel.de", "suremail.info", "tafmail.com", "teewars.org",
    "tempemail.net", "tempinbox.com", "temporaryemail.net", "temporaryinbox.com", "tempinbox.co.uk",
    "thankyou2010.com", "thisisnotmyrealemail.com", "throwawayemailaddress.com", "tittbit.in",
    "tradermail.info", "trash-mail.com", "trash-mail.de", "trash-me.com", "trashcanmail.com",
    "trashmail.at", "trashmail.io", "trashmailer.com", "trashymail.com", "tvhost.org",
    "uroid.com", "veryrealemail.com", "vidavee.com", "warimpex.at", "wegwerfadresse.de",
    "wegwerfemail.de", "wegwerfmail.de", "wegwerfmail.net", "wegwerfmail.org", "wetrainbayarea.com",
    "wetrainbayarea.org", "whyspam.me", "willselfdestruct.com", "winemaven.in", "wrongmail.com",
    "wuzupmail.net", "xagloo.com", "xemaps.com", "xents.com", "xmaily.com",
    "yapped.net", "yehey.com", "yep.it", "yogamaven.com", "yomail.info",
    "zippymail.info", "zoemail.org", "zxcvbnm.co.uk", "zzrgg.com"
}

# Suspicious keywords in domain names that indicate a throwaway email service
DISPOSABLE_PATTERNS = re.compile(
    r"(^|\.)(temp|dispos|trash|fake|throwaway|burner|guerrilla|mailinator|10minute|maildrop|generator|spambox|fakemail|yopmail|mohmal|discard|sharklaser|mytemp|jetable)[\w-]*\.[a-z]{2,}$",
    re.IGNORECASE,
)

_domains_lock = threading.Lock()
_loaded_domains: set[str] = set(PRESEEDED_DOMAINS)
_last_fetch_time: float = 0.0
_is_fetching = False


def _load_local_cache() -> None:
    """Load domains from local cache file if available."""
    global _loaded_domains
    if os.path.exists(CACHE_FILE_PATH):
        try:
            with open(CACHE_FILE_PATH, "r", encoding="utf-8", errors="ignore") as f:
                cached = {line.strip().lower() for line in f if line.strip() and not line.startswith("#")}
                if cached:
                    with _domains_lock:
                        _loaded_domains.update(cached)
        except Exception:
            pass


def _sync_remote_domains() -> None:
    """Download updated list from eramitgupta/disposable-email in background."""
    global _last_fetch_time, _is_fetching
    try:
        req = Request(
            DISPOSABLE_EMAIL_RAW_URL,
            headers={"User-Agent": "InnerWave-Disposable-Validator/1.0"},
        )
        with urlopen(req, timeout=15) as resp:
            content = resp.read().decode("utf-8", errors="ignore")
            domains = {line.strip().lower() for line in content.splitlines() if line.strip() and not line.startswith("#")}

        if domains:
            with _domains_lock:
                _loaded_domains.update(domains)
            _last_fetch_time = time.time()
            try:
                with open(CACHE_FILE_PATH, "w", encoding="utf-8") as f:
                    f.write("\n".join(sorted(_loaded_domains)))
            except Exception:
                pass
    except (URLError, Exception):
        pass
    finally:
        _is_fetching = False


def ensure_domains_loaded() -> None:
    """Ensure domains are loaded and background refresh triggered if stale."""
    global _is_fetching
    now = time.time()
    if now - _last_fetch_time > CACHE_TTL_SECONDS and not _is_fetching:
        _is_fetching = True
        thread = threading.Thread(target=_sync_remote_domains, daemon=True)
        thread.start()


# Load cache at import time
_load_local_cache()
ensure_domains_loaded()


def is_disposable_email(email: str) -> tuple[bool, str | None]:
    """
    Check if an email address belongs to a disposable or temporary email service.
    Returns (True, reason) if blocked, (False, None) if clean.
    """
    if not email or "@" not in email:
        return True, "Invalid email format."

    clean_email = email.strip().lower()
    parts = clean_email.split("@")
    if len(parts) != 2 or not parts[0] or not parts[1]:
        return True, "Invalid email format."

    domain = parts[1].strip()

    # 1. Direct domain check
    with _domains_lock:
        if domain in _loaded_domains:
            return True, f"The email provider '{domain}' is a disposable/temporary service. Please use a valid personal email (e.g. Gmail, Outlook, Yahoo, iCloud)."

    # 2. Check parent domain if it's a subdomain (e.g., mail.10minutemail.com -> 10minutemail.com)
    domain_parts = domain.split(".")
    if len(domain_parts) > 2:
        parent_domain = ".".join(domain_parts[-2:])
        with _domains_lock:
            if parent_domain in _loaded_domains:
                return True, f"The email provider '{domain}' is a disposable/temporary service. Please use a valid personal email."

    # 3. Heuristic pattern match for known throwaway keywords in the domain
    if DISPOSABLE_PATTERNS.search(domain):
        return True, f"The domain '{domain}' appears to be a disposable or temporary email service. Please use a trusted email provider."

    return False, None
