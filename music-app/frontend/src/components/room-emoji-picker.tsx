"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Search, X } from "lucide-react";

type EmojiItem = {
  emoji: string;
  name: string;
};

type EmojiCategory = {
  id: string;
  name: string;
  icon: string;
  items: EmojiItem[];
};

const CATEGORIES: EmojiCategory[] = [
  {
    id: "smileys",
    name: "Smileys",
    icon: "😀",
    items: [
      { emoji: "😀", name: "grinning face happy" },
      { emoji: "😃", name: "grinning big eyes smiling" },
      { emoji: "😄", name: "smiling face with smiling eyes" },
      { emoji: "😁", name: "beaming face grinning" },
      { emoji: "😆", name: "grinning squinting laughing" },
      { emoji: "😅", name: "sweat smile relief" },
      { emoji: "🤣", name: "rofl rolling on floor laughing" },
      { emoji: "😂", name: "tears of joy laugh" },
      { emoji: "🙂", name: "slightly smiling face" },
      { emoji: "🙃", name: "upside down face silly" },
      { emoji: "😉", name: "winking face wink" },
      { emoji: "😊", name: "smiling eyes blush warm" },
      { emoji: "😇", name: "smiling halo angel innocent" },
      { emoji: "🥰", name: "smiling face with hearts loving" },
      { emoji: "😍", name: "heart eyes love crush" },
      { emoji: "🤩", name: "star struck excited amazed" },
      { emoji: "😘", name: "blowing kiss love" },
      { emoji: "😗", name: "kissing face" },
      { emoji: "😚", name: "kissing closed eyes" },
      { emoji: "😋", name: "delicious yum tongue" },
      { emoji: "😛", name: "tongue out silly" },
      { emoji: "😜", name: "winking tongue crazy party" },
      { emoji: "🤪", name: "zany wild goofy" },
      { emoji: "😝", name: "squinting tongue playful" },
      { emoji: "🤑", name: "money mouth rich cash" },
      { emoji: "🤗", name: "smiling open hands hug" },
      { emoji: "🤭", name: "hand over mouth giggle oops" },
      { emoji: "🤫", name: "shushing quiet secret" },
      { emoji: "🤔", name: "thinking pondering hmm" },
      { emoji: "🤐", name: "zipper mouth secret quiet" },
      { emoji: "🤨", name: "raised eyebrow skeptic" },
      { emoji: "😐", name: "neutral face okay" },
      { emoji: "😑", name: "expressionless blank" },
      { emoji: "😶", name: "no mouth silent" },
      { emoji: "😏", name: "smirking cool sly" },
      { emoji: "😒", name: "unamused bored dissatisfied" },
      { emoji: "🙄", name: "face with rolling eyes whatever" },
      { emoji: "😬", name: "grimacing awkward tense" },
      { emoji: "🤥", name: "lying face pinocchio" },
      { emoji: "😌", name: "relieved peaceful calm" },
      { emoji: "😔", name: "pensive sad down" },
      { emoji: "😪", name: "sleepy tired" },
      { emoji: "🤤", name: "drooling face craving" },
      { emoji: "😴", name: "sleeping face zzz sleep" },
      { emoji: "😷", name: "medical mask sick" },
      { emoji: "🤒", name: "thermometer fever ill" },
      { emoji: "🤕", name: "head bandage hurt injured" },
      { emoji: "🤢", name: "nauseated gross disgust" },
      { emoji: "🤮", name: "vomiting sick puke" },
      { emoji: "🤧", name: "sneezing sick tissue" },
      { emoji: "🥵", name: "hot face sweating spicy" },
      { emoji: "🥶", name: "cold face freezing frost" },
      { emoji: "🥴", name: "woozy tipsy drunk dizzy" },
      { emoji: "😵", name: "dizzy face knocked out" },
      { emoji: "🤯", name: "exploding head mind blown shock" },
      { emoji: "🤠", name: "cowboy hat western" },
      { emoji: "🥳", name: "partying face celebrate hat" },
      { emoji: "😎", name: "sunglasses cool stylish" },
      { emoji: "🤓", name: "nerd face glasses geek" },
      { emoji: "🧐", name: "monocle curious inspect" },
      { emoji: "😕", name: "confused puzzled" },
      { emoji: "😟", name: "worried concerned" },
      { emoji: "🙁", name: "frowning face sad" },
      { emoji: "😮", name: "open mouth wow surprise" },
      { emoji: "😯", name: "hushed face surprise" },
      { emoji: "😲", name: "astonished shocked" },
      { emoji: "😳", name: "flushed shy embarrassed" },
      { emoji: "🥺", name: "pleading face begging cute" },
      { emoji: "😦", name: "frowning open mouth" },
      { emoji: "😧", name: "anguished troubled" },
      { emoji: "😨", name: "fearful scared" },
      { emoji: "😰", name: "anxious blue sweat stress" },
      { emoji: "😥", name: "sad relieved sweat" },
      { emoji: "😢", name: "crying tear sad" },
      { emoji: "😭", name: "loudly crying bawling sob" },
      { emoji: "😱", name: "screaming in fear panic" },
      { emoji: "😖", name: "confounded frustrated" },
      { emoji: "😣", name: "persevering struggling" },
      { emoji: "😞", name: "disappointed sorrowful" },
      { emoji: "😓", name: "downcast face with sweat" },
      { emoji: "😩", name: "weary tired upset" },
      { emoji: "😫", name: "tired fed up exhausted" },
      { emoji: "🥱", name: "yawning bored tired" },
      { emoji: "😤", name: "triumph huff proud" },
      { emoji: "😡", name: "pouting angry furious mad" },
      { emoji: "😠", name: "angry irritated" },
      { emoji: "🤬", name: "symbols on mouth swearing mad" },
      { emoji: "💀", name: "skull dead dead laughing" },
      { emoji: "☠️", name: "skull and crossbones danger" },
      { emoji: "💩", name: "poop funny pile" },
      { emoji: "🤡", name: "clown face fool" },
      { emoji: "👻", name: "ghost spooky boo" },
      { emoji: "👽", name: "alien extraterrestrial ufo" },
      { emoji: "🤖", name: "robot bot mechanical" },
      { emoji: "🎃", name: "jack o lantern halloween" },
    ],
  },
  {
    id: "hands",
    name: "Hands & Gestures",
    icon: "👋",
    items: [
      { emoji: "👋", name: "waving hand hello bye" },
      { emoji: "🤚", name: "raised back of hand" },
      { emoji: "🖐️", name: "hand with fingers splayed five" },
      { emoji: "✋", name: "raised hand high five stop" },
      { emoji: "🖖", name: "vulcan salute spock" },
      { emoji: "👌", name: "ok hand perfect fine" },
      { emoji: "🤌", name: "pinched fingers italian chef" },
      { emoji: "🤏", name: "pinching hand tiny little bit" },
      { emoji: "✌️", name: "peace sign victory two" },
      { emoji: "🤞", name: "crossed fingers luck hope" },
      { emoji: "🤟", name: "love you gesture ily" },
      { emoji: "🤘", name: "rock on horns heavy metal" },
      { emoji: "🤙", name: "call me shaka hang loose" },
      { emoji: "👈", name: "backhand index pointing left" },
      { emoji: "👉", name: "backhand index pointing right" },
      { emoji: "👆", name: "backhand index pointing up" },
      { emoji: "👇", name: "backhand index pointing down" },
      { emoji: "☝️", name: "index pointing up one listen" },
      { emoji: "👍", name: "thumbs up like approve yes" },
      { emoji: "👎", name: "thumbs down dislike no bad" },
      { emoji: "✊", name: "raised fist solidarity power" },
      { emoji: "👊", name: "oncoming fist bump punch bro" },
      { emoji: "🤛", name: "left facing fist bump" },
      { emoji: "🤜", name: "right facing fist bump" },
      { emoji: "👏", name: "clapping hands applause bravo" },
      { emoji: "🙌", name: "raising hands praise hooray celebration" },
      { emoji: "👐", name: "open hands welcoming" },
      { emoji: "🤲", name: "palms up together offering" },
      { emoji: "🤝", name: "handshake agree deal partner" },
      { emoji: "🙏", name: "folded hands pray namaste please thanks" },
      { emoji: "✍️", name: "writing hand pen note" },
      { emoji: "💅", name: "nail polish slay fabulous sass" },
      { emoji: "🤳", name: "selfie camera phone photo" },
      { emoji: "💪", name: "flexed biceps strong muscle workout" },
      { emoji: "👀", name: "eyes looking staring glance" },
      { emoji: "👁️", name: "eye see watch" },
      { emoji: "👅", name: "tongue lick taste" },
      { emoji: "👄", name: "mouth lips kiss" },
    ],
  },
  {
    id: "hearts",
    name: "Hearts & Love",
    icon: "❤️",
    items: [
      { emoji: "❤️", name: "red heart love affection" },
      { emoji: "🧡", name: "orange heart warmth friendship" },
      { emoji: "💛", name: "yellow heart joy happiness" },
      { emoji: "💚", name: "green heart nature env" },
      { emoji: "💙", name: "blue heart calm trust" },
      { emoji: "💜", name: "purple heart royalty magic" },
      { emoji: "🖤", name: "black heart dark gothic" },
      { emoji: "🤍", name: "white heart pure peace" },
      { emoji: "🤎", name: "brown heart earth" },
      { emoji: "💔", name: "broken heart breakup sorrow" },
      { emoji: "❣️", name: "heart exclamation mark" },
      { emoji: "💕", name: "two hearts affection" },
      { emoji: "💞", name: "revolving hearts romance" },
      { emoji: "💓", name: "beating heart pulse" },
      { emoji: "💗", name: "growing heart excitation" },
      { emoji: "💖", name: "sparkling heart shining" },
      { emoji: "💘", name: "heart with arrow cupid struck" },
      { emoji: "💝", name: "heart with ribbon gift present" },
      { emoji: "💟", name: "heart decoration purple" },
      { emoji: "💌", name: "love letter envelope note" },
      { emoji: "💋", name: "kiss mark lips lipstick" },
      { emoji: "💐", name: "bouquet flowers romance gift" },
      { emoji: "🌹", name: "rose red flower romance" },
      { emoji: "🥀", name: "wilted flower fading sad" },
      { emoji: "🌺", name: "hibiscus tropical flower" },
      { emoji: "🌸", name: "cherry blossom sakura pink" },
    ],
  },
  {
    id: "music",
    name: "Music & Party",
    icon: "🎵",
    items: [
      { emoji: "🎵", name: "musical note melody audio" },
      { emoji: "🎶", name: "musical notes song tune music" },
      { emoji: "🎧", name: "headphone listening audio track" },
      { emoji: "🎤", name: "microphone singing vocals karaoke" },
      { emoji: "🎙️", name: "studio microphone podcast recording" },
      { emoji: "🎸", name: "guitar rock acoustic electric music" },
      { emoji: "🎹", name: "musical keyboard piano keys" },
      { emoji: "🥁", name: "drum percussion beat rhythm" },
      { emoji: "🎷", name: "saxophone jazz brass music" },
      { emoji: "🎺", name: "trumpet fanfare horn" },
      { emoji: "🎻", name: "violin strings orchestra" },
      { emoji: "🪕", name: "banjo folk country" },
      { emoji: "📻", name: "radio broadcast vintage" },
      { emoji: "🔊", name: "speaker high volume loud sound" },
      { emoji: "🔈", name: "speaker low volume audio" },
      { emoji: "📢", name: "loudspeaker announcement" },
      { emoji: "📣", name: "megaphone cheer shouting" },
      { emoji: "🪩", name: "disco ball party dance club groove" },
      { emoji: "🎉", name: "party popper celebration celebrate hooray" },
      { emoji: "🎊", name: "confetti ball party fest" },
      { emoji: "🎈", name: "balloon birthday party celebration" },
      { emoji: "🎂", name: "birthday cake celebration dessert" },
      { emoji: "🥂", name: "clinking glasses cheers toast celebration" },
      { emoji: "🍻", name: "clinking beer mugs drinks bar party" },
      { emoji: "🍾", name: "bottle with popping cork champagne celebrate" },
      { emoji: "🍹", name: "tropical drink cocktail vacation" },
      { emoji: "🍸", name: "cocktail glass martini lounge" },
      { emoji: "🍷", name: "wine glass red dinner" },
      { emoji: "✨", name: "sparkles shining stars magic glitter" },
      { emoji: "🪄", name: "magic wand wizard spell" },
      { emoji: "🎟️", name: "admission tickets concert movie" },
      { emoji: "🎫", name: "ticket event live concert" },
    ],
  },
  {
    id: "vibes",
    name: "Vibes & Fire",
    icon: "🔥",
    items: [
      { emoji: "🔥", name: "fire flame lit hot burning" },
      { emoji: "⚡", name: "high voltage lightning electric storm" },
      { emoji: "💥", name: "collision boom explosion blast" },
      { emoji: "💫", name: "dizzy star shining swoosh" },
      { emoji: "🌟", name: "glowing star bright shining" },
      { emoji: "⭐", name: "star rating favorite" },
      { emoji: "🌈", name: "rainbow colorful sky pride" },
      { emoji: "☀️", name: "sun sunny weather bright" },
      { emoji: "🌙", name: "crescent moon night evening" },
      { emoji: "🪐", name: "ringed planet saturn space astronomy" },
      { emoji: "🚀", name: "rocket ship blast off fast launch" },
      { emoji: "💯", name: "hundred points perfect full score lit" },
      { emoji: "👑", name: "crown king queen royalty best" },
      { emoji: "💎", name: "gem stone diamond precious rare" },
      { emoji: "🏆", name: "trophy championship winner first" },
      { emoji: "🥇", name: "1st place medal gold winner" },
      { emoji: "🎖️", name: "military medal honor reward" },
      { emoji: "🎯", name: "bullseye target direct hit goal" },
      { emoji: "🎲", name: "game die dice chance gamble" },
      { emoji: "🎮", name: "video game controller console gaming" },
    ],
  },
  {
    id: "animals",
    name: "Animals",
    icon: "🐶",
    items: [
      { emoji: "🐶", name: "dog face puppy cute pet" },
      { emoji: "🐱", name: "cat face kitten meow pet" },
      { emoji: "🐭", name: "mouse face cute rodent" },
      { emoji: "🐹", name: "hamster pet cute fluffy" },
      { emoji: "🐰", name: "rabbit bunny cute hopping" },
      { emoji: "🦊", name: "fox clever wild red" },
      { emoji: "🐻", name: "bear face grizzly wild" },
      { emoji: "🐼", name: "panda face cute bamboo" },
      { emoji: "🐨", name: "koala bear australia cute" },
      { emoji: "🐯", name: "tiger face fierce striped" },
      { emoji: "🦁", name: "lion face king wild roar" },
      { emoji: "🐮", name: "cow face moo farm" },
      { emoji: "🐷", name: "pig face oink farm" },
      { emoji: "🐸", name: "frog face ribbit green" },
      { emoji: "🐵", name: "monkey face playful cheeky" },
      { emoji: "🐔", name: "chicken rooster farm" },
      { emoji: "🐧", name: "penguin arctic bird cute" },
      { emoji: "🐦", name: "bird singing flying chirp" },
      { emoji: "🦅", name: "eagle majestic bird prey" },
      { emoji: "🦉", name: "owl wise night bird" },
      { emoji: "🐺", name: "wolf howl pack moon" },
      { emoji: "🦄", name: "unicorn fantasy magical horn" },
      { emoji: "🦋", name: "butterfly beauty wings insect" },
      { emoji: "🐝", name: "honeybee buzz sweet honey" },
      { emoji: "🐢", name: "turtle slow shell reptile" },
      { emoji: "🐍", name: "snake slither reptile" },
      { emoji: "🐙", name: "octopus sea ocean tentacles" },
      { emoji: "🐬", name: "dolphin ocean sea swim" },
      { emoji: "🐳", name: "spouting whale marine ocean" },
      { emoji: "🦈", name: "shark dangerous ocean predator" },
    ],
  },
  {
    id: "food",
    name: "Food & Drinks",
    icon: "🍕",
    items: [
      { emoji: "🍕", name: "pizza slice cheese italian delicious" },
      { emoji: "🍔", name: "hamburger burger fast food beef" },
      { emoji: "🍟", name: "french fries potato fast food" },
      { emoji: "🌭", name: "hot dog sausage bun" },
      { emoji: "🍿", name: "popcorn cinema movie snack" },
      { emoji: "🥪", name: "sandwich lunch deli bread" },
      { emoji: "🌮", name: "taco mexican street food" },
      { emoji: "🌯", name: "burrito wrap mexican food" },
      { emoji: "🥗", name: "green salad healthy diet" },
      { emoji: "🍝", name: "spaghetti pasta noodles italian" },
      { emoji: "🍜", name: "steaming bowl ramen noodles soup" },
      { emoji: "🍲", name: "pot of food stew soup hearty" },
      { emoji: "🍛", name: "curry rice spicy indian dinner" },
      { emoji: "🍣", name: "sushi raw fish japanese cuisine" },
      { emoji: "🍦", name: "soft ice cream cone sweet summer" },
      { emoji: "🍧", name: "shaved ice colorful dessert" },
      { emoji: "🍩", name: "doughnut glazed sweet bakery" },
      { emoji: "🍪", name: "cookie chocolate chip sweet biscuit" },
      { emoji: "🍫", name: "chocolate bar sweet cocoa dessert" },
      { emoji: "🍬", name: "candy sweet treat sugar" },
      { emoji: "🍭", name: "lollipop candy sweet treat" },
      { emoji: "☕", name: "hot beverage coffee tea morning cup" },
      { emoji: "🍵", name: "teacup green tea matcha zen" },
      { emoji: "🧋", name: "bubble tea boba milk drink" },
      { emoji: "🥤", name: "cup with straw soft drink soda cola" },
      { emoji: "🍓", name: "strawberry red berry sweet fruit" },
      { emoji: "🍉", name: "watermelon juicy summer fruit slice" },
      { emoji: "🍇", name: "grapes wine purple fruit" },
      { emoji: "🍎", name: "red apple fruit healthy fresh" },
      { emoji: "🥑", name: "avocado healthy guacamole green" },
    ],
  },
  {
    id: "symbols",
    name: "Symbols",
    icon: "✨",
    items: [
      { emoji: "✅", name: "check mark button approved verified done" },
      { emoji: "❌", name: "cross mark cancel error reject no" },
      { emoji: "⚠️", name: "warning sign alert caution danger" },
      { emoji: "⛔", name: "no entry stop forbidden" },
      { emoji: "🚫", name: "prohibited forbidden ban no" },
      { emoji: "❓", name: "question mark help ask confused" },
      { emoji: "❗", name: "exclamation mark important attention" },
      { emoji: "‼️", name: "double exclamation mark shock" },
      { emoji: "⁉️", name: "exclamation question mark what" },
      { emoji: "💬", name: "speech balloon chat message comment" },
      { emoji: "🗨️", name: "left speech bubble message" },
      { emoji: "🗯️", name: "right anger bubble shout yell" },
      { emoji: "💭", name: "thought balloon dreaming think idea" },
      { emoji: "💤", name: "zzz sleeping tired snooze" },
      { emoji: "🆗", name: "ok button accept fine confirm" },
      { emoji: "🆒", name: "cool button awesome great" },
      { emoji: "🆕", name: "new button fresh recent" },
      { emoji: "🆙", name: "up button level up rise" },
      { emoji: "🆓", name: "free button zero cost gratis" },
      { emoji: "🔄", name: "counterclockwise arrows sync refresh reload" },
      { emoji: "🔁", name: "repeat button replay loop track" },
      { emoji: "🔂", name: "repeat single button loop once" },
      { emoji: "🔀", name: "shuffle tracks button random play" },
      { emoji: "▶️", name: "play button start video music" },
      { emoji: "⏸️", name: "pause button halt freeze" },
      { emoji: "⏹️", name: "stop button end" },
    ],
  },
];

export function RoomEmojiPicker({
  onSelect,
  onClose,
  triggerRef,
}: {
  onSelect: (emoji: string) => void;
  onClose: () => void;
  triggerRef?: React.RefObject<HTMLElement | null>;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const searchInputRef = useRef<HTMLInputElement>(null);
  const [search, setSearch] = useState("");
  const [activeCategory, setActiveCategory] = useState(0);

  // Outside click detection: auto-closes whenever clicking anywhere outside the picker or trigger
  useEffect(() => {
    function handlePointerDown(event: MouseEvent | TouchEvent) {
      const target = event.target as Node;
      if (containerRef.current?.contains(target)) return;
      if (triggerRef?.current?.contains(target)) return;
      onClose();
    }

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        onClose();
      }
    }

    document.addEventListener("mousedown", handlePointerDown);
    document.addEventListener("touchstart", handlePointerDown);
    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("mousedown", handlePointerDown);
      document.removeEventListener("touchstart", handlePointerDown);
      document.removeEventListener("keydown", handleKeyDown);
    };
  }, [onClose, triggerRef]);

  // Focus search input on mount
  useEffect(() => {
    const timer = setTimeout(() => {
      searchInputRef.current?.focus();
    }, 50);
    return () => clearTimeout(timer);
  }, []);

  const searchResults = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return null;
    const results: EmojiItem[] = [];
    const seen = new Set<string>();
    for (const cat of CATEGORIES) {
      for (const item of cat.items) {
        if (
          (item.name.toLowerCase().includes(query) || item.emoji.includes(query)) &&
          !seen.has(item.emoji)
        ) {
          seen.add(item.emoji);
          results.push(item);
        }
      }
    }
    return results;
  }, [search]);

  const displayedItems = searchResults ?? CATEGORIES[activeCategory].items;

  return (
    <div
      ref={containerRef}
      className="room-emoji-picker-popover"
      role="dialog"
      aria-label="Emoji Picker"
      onClick={(e) => e.stopPropagation()}
    >
      <div className="room-emoji-picker-search">
        <Search size={14} />
        <input
          ref={searchInputRef}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search 300+ emojis…"
        />
        {search && (
          <button
            type="button"
            className="room-emoji-picker-clear"
            onClick={() => setSearch("")}
            title="Clear search"
          >
            <X size={13} />
          </button>
        )}
      </div>

      {!searchResults && (
        <div className="room-emoji-picker-tabs">
          {CATEGORIES.map((cat, index) => (
            <button
              key={cat.id}
              type="button"
              className={`room-emoji-picker-tab ${activeCategory === index ? "active" : ""}`}
              onClick={() => setActiveCategory(index)}
              title={cat.name}
            >
              <span>{cat.icon}</span>
            </button>
          ))}
        </div>
      )}

      <div className="room-emoji-picker-header">
        <span>{searchResults ? `Search results (${searchResults.length})` : CATEGORIES[activeCategory].name}</span>
      </div>

      <div className="room-emoji-picker-grid">
        {displayedItems.length === 0 ? (
          <div className="room-emoji-picker-empty">
            <span>No emojis found for &ldquo;{search}&rdquo;</span>
          </div>
        ) : (
          displayedItems.map((item) => (
            <button
              key={item.emoji}
              type="button"
              className="room-emoji-btn"
              onClick={() => onSelect(item.emoji)}
              title={item.name}
            >
              {item.emoji}
            </button>
          ))
        )}
      </div>
    </div>
  );
}
