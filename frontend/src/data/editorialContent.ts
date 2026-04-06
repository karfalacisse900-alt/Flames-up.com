// Editorial story data for Flames-Up Discover page

export type Story = {
  id: string;
  title: string;
  subtitle: string;
  category: string;
  location: string;
  image: string;
  body: string;
  author: string;
  authorImage?: string;
  readTime: string;
  featured?: boolean;
  type: 'story' | 'voice' | 'spotlight';
};

export const EDITORIAL_STORIES: Story[] = [
  {
    id: 'ed-1', type: 'story', featured: true,
    title: 'Why NYC street food hits different at 2AM',
    subtitle: 'From halal carts to taco trucks \u2014 the city that never stops eating',
    category: 'food', location: 'NYC',
    image: 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=800&q=80',
    body: "There is something almost sacred about standing on a New York City corner at 2 in the morning, steam rising from a halal cart, the sounds of the city still very much alive around you. The sidewalk becomes a dining room, and strangers become companions over lamb over rice.\n\nNew York\u2019s street food scene is not just about convenience \u2014 it is a cultural institution. From the legendary Halal Guys on 53rd and 6th to the late-night taco trucks of Sunset Park, the options are as diverse as the city itself.\n\nWhat makes it hit different at night? Perhaps it is the honesty of it. No reservations, no dress codes, no pretense. Just good food served fast to people who are genuinely hungry.",
    author: 'Flames-Up Editorial', readTime: '4 min read',
  },
  {
    id: 'ed-2', type: 'story',
    title: "Inside Tokyo\u2019s hidden night caf\u00e9s",
    subtitle: 'Where jazz meets espresso in the backstreets of Shibuya',
    category: 'culture', location: 'Tokyo',
    image: 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?w=800&q=80',
    body: "Tokyo\u2019s kissaten culture runs deep. These traditional coffee houses, tucked away in narrow alleys, offer more than just caffeine. They offer an escape. Dimly lit, with vinyl spinning on vintage turntables, each kissaten tells its own story through its collection of jazz records and hand-dripped coffee.\n\nIn Shibuya\u2019s backstreets, away from the neon-lit scramble crossing, you will find caf\u00e9s that have been operating for over 40 years. The owners know every regular by name and by drink order.",
    author: 'Flames-Up Editorial', readTime: '5 min read',
  },
  {
    id: 'ed-3', type: 'story',
    title: 'The art of doing nothing in Paris',
    subtitle: 'Why sitting at a caf\u00e9 is a Parisian art form',
    category: 'culture', location: 'Paris',
    image: 'https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=800&q=80',
    body: "In Paris, sitting at a caf\u00e9 terrace is not wasting time \u2014 it is an art form called fl\u00e2nerie. The French have perfected the art of people-watching, espresso-sipping, and simply being present.",
    author: 'Flames-Up Editorial', readTime: '3 min read',
  },
  {
    id: 'ed-4', type: 'story',
    title: "Miami\u2019s Cuban coffee revolution",
    subtitle: 'How colada culture fuels the Magic City',
    category: 'food', location: 'Miami',
    image: 'https://images.unsplash.com/photo-1514432324607-a09d9b4aefda?w=800&q=80',
    body: "In Miami, coffee is not just a drink \u2014 it is a social ritual. The ventanita (little window) is where deals are made, gossip is shared, and the day truly begins. A tiny cup of cafecito, thick and sweet, is the currency of connection.",
    author: 'Flames-Up Editorial', readTime: '3 min read',
  },
  {
    id: 'ed-5', type: 'story',
    title: "London\u2019s Borough Market at dawn",
    subtitle: 'Before the tourists arrive, the real magic happens',
    category: 'food', location: 'London',
    image: 'https://images.unsplash.com/photo-1534531173927-aeb928d54385?w=800&q=80',
    body: "At 5AM, Borough Market belongs to the vendors. The air smells of fresh bread and coffee. Fishmongers arrange their catches on ice while cheese makers unwrap wheels of aged cheddar.",
    author: 'Flames-Up Editorial', readTime: '4 min read',
  },
  {
    id: 'ed-6', type: 'story',
    title: 'Harajuku is dead. Long live Harajuku.',
    subtitle: 'How Tokyo street style evolved beyond the stereotypes',
    category: 'style', location: 'Tokyo',
    image: 'https://images.unsplash.com/photo-1542051841857-5f90071e7989?w=800&q=80',
    body: "The Harajuku you see in travel guides \u2014 rainbow tutus and gothic lolita \u2014 barely exists anymore. What replaced it is something more subtle, more personal, and arguably more influential.",
    author: 'Flames-Up Editorial', readTime: '5 min read',
  },
  {
    id: 'ed-7', type: 'story',
    title: 'Thrifting culture in Brooklyn',
    subtitle: 'Why secondhand is the new luxury',
    category: 'style', location: 'NYC',
    image: 'https://images.unsplash.com/photo-1558618666-fcd25c85f82e?w=800&q=80',
    body: "In Williamsburg and Bushwick, thrift stores have become cultural institutions. The hunt for a vintage Carhartt jacket or a perfect pair of 501s is a weekend ritual.",
    author: 'Flames-Up Editorial', readTime: '3 min read',
  },
  {
    id: 'ed-8', type: 'story',
    title: 'The underground DJ scene in Berlin',
    subtitle: 'Where techno is still a way of life, not a trend',
    category: 'nightlife', location: 'Global',
    image: 'https://images.unsplash.com/photo-1571266028243-e4733b0f0bb0?w=800&q=80',
    body: "Berlin does not just have nightlife \u2014 it IS nightlife. In warehouse clubs where the bass hits your chest and time loses all meaning, the city\u2019s creative spirit comes alive after dark.",
    author: 'Flames-Up Editorial', readTime: '4 min read',
  },
  {
    id: 'ed-9', type: 'story',
    title: 'Mezcal bars are taking over LA',
    subtitle: 'The smoky spirit is having its moment on the West Coast',
    category: 'nightlife', location: 'LA',
    image: 'https://images.unsplash.com/photo-1551024709-8f23befc6f87?w=800&q=80',
    body: "From Highland Park to Venice, mezcal bars are popping up in converted garages and behind unmarked doors. The smoky agave spirit has become LA\u2019s drink of choice.",
    author: 'Flames-Up Editorial', readTime: '3 min read',
  },
  {
    id: 'ed-10', type: 'story',
    title: "What commuters won\u2019t tell you about the subway",
    subtitle: 'The hidden culture of NYC underground',
    category: 'city_life', location: 'NYC',
    image: 'https://images.unsplash.com/photo-1474487548417-781cb71495f3?w=800&q=80',
    body: "Every car is a stage. Mariachi bands, breakdancers, saxophonists playing Coltrane. The subway is New York\u2019s most democratic public space.",
    author: 'Flames-Up Editorial', readTime: '4 min read',
  },
];

export const VOICES: Story[] = [
  {
    id: 'v-1', type: 'voice',
    title: 'My favorite thrift spots in NYC',
    subtitle: 'A personal guide to vintage hunting in Brooklyn',
    category: 'style', location: 'NYC',
    image: 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=800&q=80',
    body: "Every Saturday morning I take the L train to Bushwick. My route is always the same: first, the Salvation Army on Broadway for denim. Then L Train Vintage for band tees. Then a pit stop at the corner bodega for a bacon egg and cheese.",
    author: 'Maya R.', readTime: '3 min read',
  },
  {
    id: 'v-2', type: 'voice',
    title: 'How I spend Sundays in Queens',
    subtitle: 'From dim sum to cricket matches',
    category: 'city_life', location: 'NYC',
    image: 'https://images.unsplash.com/photo-1517457373958-b7bdd4587205?w=800&q=80',
    body: "Sundays in Queens start at Nan Xiang in Flushing for soup dumplings, then a walk through the park where Pakistani cricket teams play until sundown.",
    author: 'Amir K.', readTime: '2 min read',
  },
  {
    id: 'v-3', type: 'voice',
    title: 'Why I moved to Miami for the music',
    subtitle: 'Reggaeton, Afrobeats, and everything in between',
    category: 'nightlife', location: 'Miami',
    image: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?w=800&q=80',
    body: "Miami\u2019s music scene is what happens when Caribbean, Latin, and African rhythms collide. On any given Friday in Wynwood, you can hear all three within a two-block walk.",
    author: 'Daniela V.', readTime: '3 min read',
  },
];

export const SPOTLIGHTS: Story[] = [
  {
    id: 's-1', type: 'spotlight',
    title: 'This Harlem barber is changing the game',
    subtitle: "Marcus\u2019s chair is where community meets craft",
    category: 'city_life', location: 'NYC',
    image: 'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?w=800&q=80',
    body: "Marcus has been cutting hair in Harlem for 23 years. His barbershop is more than a business \u2014 it is a mentoring center, a music studio, and a gathering place.",
    author: 'Flames-Up Spotlight', readTime: '4 min read',
  },
  {
    id: 's-2', type: 'spotlight',
    title: "Best hidden caf\u00e9 in Brooklyn",
    subtitle: 'A converted garage that makes the best pour-over in NYC',
    category: 'food', location: 'NYC',
    image: 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=800&q=80',
    body: "Tucked behind a laundromat on a quiet Bed-Stuy side street, this caf\u00e9 has no sign, no social media, and a two-week wait for a bag of their house roast.",
    author: 'Flames-Up Spotlight', readTime: '3 min read',
  },
  {
    id: 's-3', type: 'spotlight',
    title: 'The Tokyo vinyl shop with 50K records',
    subtitle: 'Where crate diggers from around the world come to hunt',
    category: 'culture', location: 'Tokyo',
    image: 'https://images.unsplash.com/photo-1483412033650-1015ddeb83d1?w=800&q=80',
    body: "In Shimokitazawa, a shop the size of a New York studio apartment holds one of the most impressive vinyl collections in the world.",
    author: 'Flames-Up Spotlight', readTime: '3 min read',
  },
];

// Combined lookup for story detail page
export const ALL_STORIES_MAP: Record<string, Story> = {};
[...EDITORIAL_STORIES, ...VOICES, ...SPOTLIGHTS].forEach(s => {
  ALL_STORIES_MAP[s.id] = s;
});
