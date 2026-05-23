export type LegalPageKey = 'terms' | 'privacy' | 'community-guidelines' | 'safety';

export type LegalSection = {
  title: string;
  paragraphs?: string[];
  bullets?: string[];
};

export type LegalPage = {
  key: LegalPageKey;
  title: string;
  shortTitle: string;
  route: string;
  icon: string;
  summary: string;
  sections: LegalSection[];
};

export const LEGAL_LAST_UPDATED = 'May 23, 2026';
export const SUPPORT_EMAIL = 'karfalacisse900@gmail.com';
export const WEBSITE_DOMAIN = '[insert domain, for example captro.app or getcaptro.com]';
export const LEGAL_DISCLAIMER = 'These pages are provided for general information and should be reviewed by a qualified legal professional before public launch.';

const termsSections: LegalSection[] = [
  {
    title: 'What Captro Is',
    paragraphs: [
      'Captro is a social media, photo, and short-video sharing app for capturing moments, posting photos and videos, discovering visual content, and connecting with people through profiles, chat, feed posts, stories, fullscreen media, notifications, and gallery-style discovery.',
      'These Terms explain the rules for using Captro. If you do not agree, do not use the app.',
    ],
  },
  {
    title: 'Eligibility and Accounts',
    paragraphs: [
      'You must be at least 13 years old, or the minimum age required in your country if higher, to use Captro. If you are under the age of majority where you live, you should use Captro only with permission from a parent or guardian.',
      'You are responsible for your account, login credentials, profile details, username, and activity. Keep your password private and tell us if you believe your account has been accessed without permission.',
    ],
    bullets: [
      'Usernames, display names, profile photos, bios, and links must not impersonate others, mislead people, promote hate, or violate another person\'s rights.',
      'You may not sell, transfer, automate, or misuse an account in a way that harms Captro or other users.',
    ],
  },
  {
    title: 'User Content and License',
    paragraphs: [
      'You own the photos, videos, captions, comments, messages, profile information, stories, gallery posts, and other content you create or upload, subject to any rights held by others.',
      'To operate Captro, you give Captro permission to host, store, process, resize, transcode, display, distribute inside the app, moderate, and otherwise use your content only as needed to provide, improve, protect, and promote Captro features.',
    ],
    bullets: [
      'Public or shared content such as feed posts, profile posts, Discover posts, gallery posts, stories, comments, likes, saves, shares, and profile details may be visible to other users.',
      'Private chat messages are not public posts. They may still be processed to deliver the service, enforce safety rules, investigate reports, prevent abuse, or comply with law.',
      'Do not upload photos, videos, music, captions, screenshots, or other content unless you own it or have permission to use it.',
    ],
  },
  {
    title: 'Prohibited Content and Behavior',
    paragraphs: ['You may not use Captro to harm people, abuse the platform, or violate the law.'],
    bullets: [
      'No harassment, bullying, threats, hate speech, violence, incitement, exploitation, sexual content involving minors, doxxing, stalking, or sharing private personal information.',
      'No scams, spam, fake engagement, impersonation, stolen content, copyright violations, illegal activity, dangerous behavior, ban evasion, or attempts to bypass safety systems.',
      'Do not use chat to harass, threaten, scam, spam, exploit, pressure, send unwanted explicit content, ask for money, coerce, or share private information.',
      'Do not use location, place, or check-in features to stalk, expose, threaten, harass, or mislead people about another person\'s location.',
    ],
  },
  {
    title: 'Reporting, Blocking, and Moderation',
    paragraphs: [
      'Captro may provide reporting, blocking, moderation, and admin review tools. Reports may be reviewed by moderation systems, admins, or service providers helping us keep the app safe.',
      'Captro may remove or restrict posts, comments, profiles, stories, Discover content, gallery content, messages, places, or accounts. Captro may also suspend or remove accounts, preserve safety records, and review ban evasion.',
    ],
  },
  {
    title: 'Copyright, Availability, Liability, and Changes',
    paragraphs: [
      'Respect copyright and intellectual property rights. If you believe content infringes your rights, contact support with enough detail for us to review it.',
      'Captro is provided as available. We do not guarantee uninterrupted access, error-free service, or that every feature will remain available. Features may change, be removed, or be added over time.',
      'To the fullest extent allowed by law, Captro is not responsible for user-generated content, offline interactions, service interruptions, lost data, or indirect damages. We may update these Terms and continued use means acceptance of the updated Terms.',
    ],
  },
];

const privacySections: LegalSection[] = [
  {
    title: 'Information You Provide',
    paragraphs: ['Captro may collect information you provide when creating or using an account, communicating with other users, posting media, reporting content, or contacting support.'],
    bullets: [
      'Name or display name, username, email address, password or login credentials, profile photo, bio, links, and account details.',
      'Posts, photos, videos, captions, comments, likes, saves, follows or friends, reports, support messages, and other activity you choose to create.',
    ],
  },
  {
    title: 'Chat and Message Data',
    paragraphs: ['Captro processes messages you send and receive so private chat can work. Private messages are not public posts, but they may be processed to provide the service, enforce safety, investigate reports, prevent abuse, or comply with law.'],
    bullets: ['Message content and attachments.', 'Message metadata such as sender, receiver, timestamps, delivery status, read status if used, and safety signals.'],
  },
  {
    title: 'Discover, Gallery, Stories, and Media Data',
    paragraphs: ['Captro may process posts shown in Feed, Discover, profile grids, stories, fullscreen viewers, and gallery-style surfaces. We may generate thumbnails, previews, optimized feed versions, and playback versions while preserving the original upload when technically possible.'],
    bullets: ['Views, interactions, likes, saves, comments, shares, reports, and other usage activity may be used to operate and improve the app.', 'Public content may be visible to other users. Do not post private information you do not want others to see.'],
  },
  {
    title: 'Location and Permissions',
    paragraphs: ['If Captro offers location, place, nearby, or check-in features, we may process approximate location, precise location with permission, place tags, check-ins, and related content.', 'You can control camera, photos, microphone, notifications, and location permissions in your device settings.'],
  },
  {
    title: 'Device, Technical, and Usage Data',
    paragraphs: ['Captro may collect device type, operating system, app version, IP address, log data, crash reports, performance data, security signals, and usage activity.'],
    bullets: ['We use this information to keep Captro reliable, secure, and smooth.', 'We may use logs and security signals to detect spam, abuse, scams, fraud, ban evasion, and unauthorized access.'],
  },
  {
    title: 'How Information Is Used',
    paragraphs: ['Captro uses information to create and manage accounts, show Feed, Profile, Discover, chat, stories, posts, comments, notifications, gallery content, and support requests.'],
    bullets: ['Improve app performance, media quality, loading states, safety, moderation, recommendations, and user experience.', 'Detect and respond to spam, abuse, scams, fraud, security issues, policy violations, and legal obligations.'],
  },
  {
    title: 'How Information Is Shared',
    paragraphs: ['We do not sell personal information. Information may be shared when needed to operate the app, comply with law, keep people safe, or complete a business transfer if applicable.'],
    bullets: ['With other users when your content, profile, comments, stories, posts, or interactions are public or shared through app features.', 'With service providers for hosting, storage, analytics, maps, notifications, media processing, security, support, and moderation.', 'If required by law, legal process, safety needs, or to protect Captro, users, or the public.'],
  },
  {
    title: 'Deletion, Retention, and Choices',
    paragraphs: ['You can request account deletion through the app if available or by contacting support at karfalacisse900@gmail.com. Some information may be retained when needed for safety, security, fraud prevention, legal compliance, dispute resolution, or moderation records.'],
  },
];

const communitySections: LegalSection[] = [
  {
    title: 'The Captro Culture',
    paragraphs: ['Captro is for real people, original photos and videos, captured moments, creativity, respectful comments, safe messaging, useful Discover and gallery content, and genuine connection.'],
    bullets: ['Share content you created or have permission to share.', 'Treat people with respect in comments, messages, profiles, stories, and Discover.', 'Avoid spammy, stolen, fake, or misleading content.'],
  },
  {
    title: 'Content That Is Not Allowed',
    paragraphs: ['The following content and behavior may be removed and may lead to account limits, suspension, or permanent bans.'],
    bullets: ['Harassment, bullying, threats, hate speech, violence, incitement, sexual exploitation, sexual content involving minors, and dangerous behavior.', 'Doxxing, private personal information, stalking, impersonation, scams, spam, fake engagement, stolen content, copyright violations, illegal activity, and ban evasion.', 'Abuse of reporting, blocking, moderation, or safety tools.'],
  },
  {
    title: 'Chat Rules',
    paragraphs: ['Private messages must follow the same safety standards as public areas. Chat should never be used to pressure, threaten, exploit, stalk, or scam people.'],
    bullets: ['No harassment, threats, unwanted explicit content, sexual exploitation, scams, spam, coercion, or requests for money from strangers.', 'Do not share another person\'s private personal information, private photos, documents, address, phone number, or financial details.'],
  },
  {
    title: 'Discover, Gallery, Feed, and Stories',
    paragraphs: ['Discover posts, gallery-style visual content, feed posts, stories, profile grids, comments, and fullscreen media must follow these Guidelines.'],
    bullets: ['No stolen images or videos.', 'No misleading content, spam galleries, unsafe content, abusive content, or manipulated engagement.', 'Use captions, tags, and locations honestly and respectfully.'],
  },
  {
    title: 'Location and Check-In Safety',
    paragraphs: ['If location, place, or check-in features are available, use them safely. Do not expose someone else\'s private location, stalk or follow people, fake harmful location claims, or use places/check-ins to harass businesses or people.'],
  },
  {
    title: 'Enforcement',
    paragraphs: ['Captro may use warnings, content removal, feature limits, account suspension, permanent bans, and device, IP, or behavior-based ban evasion review where available.'],
  },
];

const safetySections: LegalSection[] = [
  {
    title: 'How to Report',
    paragraphs: ['Use in-app reporting tools where available to report posts, comments, profiles, messages, chat conversations, stories, Discover posts, gallery posts, check-ins, places, or other unsafe activity.'],
    bullets: ['Choose the closest report reason and include helpful context when the app allows it.', 'For urgent support or account issues, contact karfalacisse900@gmail.com.'],
  },
  {
    title: 'Blocking',
    paragraphs: ['Blocking helps stop unwanted interaction where supported. Depending on app behavior, blocked users may be limited from messaging, commenting, or viewing certain profile activity.'],
  },
  {
    title: 'After a Report',
    paragraphs: ['Reports may be reviewed through moderation/admin tools. Captro may remove content, warn users, limit features, suspend accounts, or ban accounts. Reports may not always receive individual responses.', 'If there is immediate danger, contact local emergency services first. Captro is not an emergency service.'],
  },
  {
    title: 'Personal Safety Advice',
    paragraphs: ['Be careful with what you share and who you trust online.'],
    bullets: ['Do not share your personal address, phone number, financial information, private photos, sensitive documents, passwords, or verification codes.', 'Be careful meeting people from chat. If you meet someone offline, meet in public, tell someone you trust, and leave if you feel unsafe.', 'Do not send money to strangers.', 'Report threats, harassment, scams, doxxing, exploitation, stalking, or coercive behavior.'],
  },
  {
    title: 'Chat Safety',
    paragraphs: ['You can report messages and block abusive users where supported. Captro may review reported messages or safety-related content when necessary to investigate reports, enforce policies, protect users, or comply with law.'],
  },
];

export const legalPages: Record<LegalPageKey, LegalPage> = {
  terms: {
    key: 'terms',
    title: 'Terms of Service',
    shortTitle: 'Terms',
    route: '/legal/terms',
    icon: 'document-text-outline',
    summary: 'The rules for using Captro, posting photos and videos, using chat, and participating safely in Feed, Profile, Discover, Stories, and gallery-style experiences.',
    sections: termsSections,
  },
  privacy: {
    key: 'privacy',
    title: 'Privacy Policy',
    shortTitle: 'Privacy',
    route: '/legal/privacy',
    icon: 'hand-left-outline',
    summary: 'How Captro collects, uses, shares, protects, and retains account, media, chat, location, device, and safety information.',
    sections: privacySections,
  },
  'community-guidelines': {
    key: 'community-guidelines',
    title: 'Community Guidelines',
    shortTitle: 'Guidelines',
    route: '/legal/community-guidelines',
    icon: 'people-outline',
    summary: 'The culture and safety rules for posts, comments, chat, Discover, stories, check-ins, profiles, and gallery content.',
    sections: communitySections,
  },
  safety: {
    key: 'safety',
    title: 'Safety & Reporting',
    shortTitle: 'Safety',
    route: '/legal/safety',
    icon: 'shield-checkmark-outline',
    summary: 'How to report content, block users, stay safer in chat, and understand what may happen after a report.',
    sections: safetySections,
  },
};

export const legalPageList = Object.values(legalPages);
