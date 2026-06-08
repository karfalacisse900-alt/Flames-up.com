import SwiftUI

private let captroLegalLastUpdated = "June 8, 2026"
private let captroSupportEmail = "karfalacisse900@gmail.com"
private let captroWebsiteDomain = "https://flames-up.com"
private let captroLegalDisclaimer = "Captro may update these pages as the app, safety tools, or legal requirements change."

private struct LegalSection: Identifiable {
  let title: String
  let paragraphs: [String]
  let bullets: [String]

  var id: String { title }
}

private enum CaptroLegalPage: CaseIterable, Hashable {
  case terms
  case privacy
  case communityGuidelines
  case safety

  var title: String {
    switch self {
    case .terms: return "Terms of Service"
    case .privacy: return "Privacy Policy"
    case .communityGuidelines: return "Community Guidelines"
    case .safety: return "Safety & Reporting"
    }
  }

  var shortTitle: String {
    switch self {
    case .terms: return "Terms"
    case .privacy: return "Privacy"
    case .communityGuidelines: return "Guidelines"
    case .safety: return "Safety"
    }
  }

  var route: String {
    switch self {
    case .terms: return "/legal/terms"
    case .privacy: return "/legal/privacy"
    case .communityGuidelines: return "/legal/community-guidelines"
    case .safety: return "/legal/safety"
    }
  }

  var icon: String {
    switch self {
    case .terms: return "doc.text"
    case .privacy: return "hand.raised"
    case .communityGuidelines: return "person.2"
    case .safety: return "shield.lefthalf.filled"
    }
  }

  var summary: String {
    switch self {
    case .terms:
      return "The rules for using Captro, posting photos and videos, using chat, and participating safely in Feed, Profile, Discover, Stories, and gallery-style experiences."
    case .privacy:
      return "How Captro collects, uses, shares, protects, and retains account, media, chat, location, device, and safety information."
    case .communityGuidelines:
      return "The culture and safety rules for posts, comments, chat, Discover, stories, check-ins, profiles, and gallery content."
    case .safety:
      return "How to report content, block users, stay safer in chat, and understand what may happen after a report."
    }
  }

  var sections: [LegalSection] {
    switch self {
    case .terms: return termsSections
    case .privacy: return privacySections
    case .communityGuidelines: return communitySections
    case .safety: return safetySections
    }
  }
}

public struct TermsOfServiceView: View {
  public init() {}
  public var body: some View { LegalDocumentView(page: .terms) }
}

public struct PrivacyPolicyView: View {
  public init() {}
  public var body: some View { LegalDocumentView(page: .privacy) }
}

public struct CommunityGuidelinesView: View {
  public init() {}
  public var body: some View { LegalDocumentView(page: .communityGuidelines) }
}

public struct SafetyReportingView: View {
  public init() {}
  public var body: some View { LegalDocumentView(page: .safety) }
}

private struct LegalDestinationView: View {
  let page: CaptroLegalPage

  var body: some View {
    switch page {
    case .terms: TermsOfServiceView()
    case .privacy: PrivacyPolicyView()
    case .communityGuidelines: CommunityGuidelinesView()
    case .safety: SafetyReportingView()
    }
  }
}

private struct LegalDocumentView: View {
  let page: CaptroLegalPage

  var body: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: MIRATheme.Space.lg) {
        legalHero

        ForEach(page.sections) { section in
          LegalSectionCard(section: section)
        }

        supportCard
        LegalFooterLinks(current: page)
      }
      .padding(.horizontal, MIRATheme.Space.md)
      .padding(.top, MIRATheme.Space.md)
      .padding(.bottom, MIRATheme.Space.xxl)
    }
    .background(MIRATheme.Color.appBackground.ignoresSafeArea())
    .navigationTitle(page.shortTitle)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var legalHero: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.md) {
      HStack(alignment: .top, spacing: MIRATheme.Space.md) {
        Image(systemName: page.icon)
          .font(.system(size: 21, weight: .semibold))
          .foregroundStyle(MIRATheme.Color.forest)
          .frame(width: 48, height: 48)
          .background(MIRATheme.Color.forestSoft)
          .clipShape(Circle())

        VStack(alignment: .leading, spacing: 6) {
          Text(page.title)
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
          Text("Last updated: \(captroLegalLastUpdated)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MIRATheme.Color.textMuted)
          Text(page.route)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
      }

      Text(page.summary)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)

      Text("Website/domain: \(captroWebsiteDomain)")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textMuted)
    }
    .padding(MIRATheme.Space.lg)
    .miraCardSurface(cornerRadius: 24)
  }

  private var supportCard: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
      Text("Questions or Requests")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Text("For support, safety, privacy, account deletion, or legal questions, contact Captro support.")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Link(captroSupportEmail, destination: URL(string: "mailto:\(captroSupportEmail)")!)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.forest)
      Text(captroLegalDisclaimer)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(MIRATheme.Color.textMuted)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, MIRATheme.Space.xs)
    }
    .padding(MIRATheme.Space.lg)
    .background(MIRATheme.Color.forestSoft)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
  }
}

private struct LegalSectionCard: View {
  let section: LegalSection

  var body: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
      Text(section.title)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)

      ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
        Text(paragraph)
          .font(.system(size: 14.5, weight: .regular))
          .foregroundStyle(MIRATheme.Color.textSecondary)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)
      }

      if !section.bullets.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
            HStack(alignment: .top, spacing: MIRATheme.Space.sm) {
              Circle()
                .fill(MIRATheme.Color.forest)
                .frame(width: 5, height: 5)
                .padding(.top, 8)
              Text(bullet)
                .font(.system(size: 14.5, weight: .regular))
                .foregroundStyle(MIRATheme.Color.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .padding(.top, MIRATheme.Space.xs)
      }
    }
    .padding(MIRATheme.Space.lg)
    .background(MIRATheme.Color.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(MIRATheme.Color.hairline, lineWidth: 1))
    .modifier(MIRATheme.softShadow())
  }
}

private struct LegalFooterLinks: View {
  let current: CaptroLegalPage

  var body: some View {
    VStack(alignment: .leading, spacing: MIRATheme.Space.sm) {
      Text("LEGAL")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(MIRATheme.Color.textMuted)

      VStack(spacing: 0) {
        ForEach(CaptroLegalPage.allCases.filter { $0 != current }, id: \.self) { page in
          NavigationLink {
            LegalDestinationView(page: page)
          } label: {
            HStack(spacing: MIRATheme.Space.sm) {
              Image(systemName: page.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.forest)
                .frame(width: 34, height: 34)
                .background(MIRATheme.Color.surfaceSoft)
                .clipShape(Circle())
              VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                  .font(.system(size: 15, weight: .semibold))
                  .foregroundStyle(MIRATheme.Color.textPrimary)
                Text(page.route)
                  .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                  .foregroundStyle(MIRATheme.Color.textMuted)
              }
              Spacer()
              Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MIRATheme.Color.textMuted)
            }
            .padding(.horizontal, MIRATheme.Space.md)
            .padding(.vertical, 12)
          }
          .buttonStyle(.plain)
        }
      }
      .background(MIRATheme.Color.surfaceRaised)
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MIRATheme.Color.hairline, lineWidth: 1))
    }
  }
}

private let termsSections: [LegalSection] = [
  LegalSection(
    title: "What Captro Is",
    paragraphs: [
      "Captro is a social app for sharing photo posts, multi-photo posts, stories, comments, chat messages, profiles, bookmarks, Discover content, and other creative moments.",
      "These Terms explain the rules for using Captro. By creating an account or using Captro, you agree to follow these Terms, the Privacy Policy, the Community Guidelines, and the Safety & Reporting rules."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Age Requirement: 16+",
    paragraphs: [
      "You must be at least 16 years old to use Captro. Captro is not made for children under 16, and people under 16 are not allowed to create or use an account.",
      "If we learn that an account belongs to someone under 16, we may remove the account and delete or limit related information. If you believe someone under 16 is using Captro, contact support."
    ],
    bullets: [
      "If you are 16 or older but still under the legal age of majority where you live, use Captro only with permission from a parent or guardian.",
      "Do not lie about your age, create accounts for someone under 16, or help someone bypass the age requirement."
    ]
  ),
  LegalSection(
    title: "Your Account",
    paragraphs: [
      "You are responsible for your account, username, profile, login credentials, and activity. Keep your password private and tell us if you believe your account was accessed without permission.",
      "Captro may support email/password login, Sign in with Apple, Google sign-in, or other approved authentication methods. You must use accurate account information and may not impersonate another person."
    ],
    bullets: [
      "Do not sell, transfer, rent, automate, scrape, spam, or misuse an account.",
      "Usernames, display names, photos, bios, links, and profile details must not impersonate, mislead, harass, promote hate, or violate another person's rights.",
      "Banned users may not create new accounts to avoid enforcement."
    ]
  ),
  LegalSection(
    title: "User Content and License",
    paragraphs: [
      "You own the content you create or upload, subject to any rights held by other people. This can include photos, story videos, captions, comments, profile details, messages, places, reports, and other content.",
      "To run Captro, you give Captro a worldwide, non-exclusive, royalty-free license to host, store, process, resize, optimize, moderate, display, and distribute your content inside Captro and related Captro services. This permission is only for operating, protecting, improving, and promoting Captro features."
    ],
    bullets: [
      "Public or shared content may appear in Feed, Discover, profiles, bookmarks, stories, comments, search, notifications, or other app surfaces depending on your settings and the feature used.",
      "Private chat messages are not public posts, but they may still be processed to deliver messages, investigate reports, prevent abuse, enforce safety rules, and comply with law.",
      "Do not upload media, music, screenshots, captions, or other content unless you own it or have permission to use it."
    ]
  ),
  LegalSection(
    title: "Posting, Stories, Chat, and Location",
    paragraphs: [
      "Captro may allow photo posts, multi-photo posts, story videos, comments, direct messages, profile content, and optional location or place features. Use these features safely and respectfully.",
      "Exact place tags and broad city/country labels are optional where available. Do not use location features to expose private places, stalk, harass, threaten, or mislead people."
    ],
    bullets: [
      "Do not post someone else's private address, live location, phone number, financial information, private documents, or sensitive personal information.",
      "Do not use chat for threats, scams, harassment, coercion, unwanted explicit content, spam, exploitation, or requests for money from strangers.",
      "If you choose to share a place, city, country, or location label, you are responsible for what you share."
    ]
  ),
  LegalSection(
    title: "Not Allowed",
    paragraphs: [
      "You may not use Captro to harm people, abuse the service, or break the law. Captro may remove content, limit features, suspend accounts, ban accounts, or preserve safety records when rules are broken."
    ],
    bullets: [
      "No harassment, bullying, threats, hate speech, violence, gore, sexual exploitation, sexual content involving minors, doxxing, stalking, or private information abuse.",
      "No scams, spam, fake engagement, impersonation, stolen content, copyright violations, illegal activity, dangerous behavior, malware, phishing, or ban evasion.",
      "No attempts to bypass security, moderation, account limits, upload limits, location privacy, reporting tools, or backend protections."
    ]
  ),
  LegalSection(
    title: "Moderation and Safety Review",
    paragraphs: [
      "Captro may use automated systems, human review, admin tools, user reports, safety signals, and service providers to review content and accounts. Media may be checked before becoming public.",
      "Captro may remove or restrict posts, comments, profiles, stories, Discover content, messages, places, accounts, or other content if it may violate these Terms or safety rules."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Account Deletion",
    paragraphs: [
      "You may request account deletion inside the app where available or by contacting support. Captro may first place the account in a deletion-pending state, hide it from public areas, log out sessions, and permanently delete or anonymize eligible account data after a 30-day deletion period.",
      "Some information may be kept when needed for safety, security, legal compliance, fraud prevention, dispute resolution, audit logs, or ban evasion prevention."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Copyright, Service Availability, and Changes",
    paragraphs: [
      "Respect copyright and intellectual property rights. If you believe content infringes your rights, contact support with enough detail for us to review it.",
      "Captro is provided as available. We do not guarantee uninterrupted service, error-free features, or that every feature will remain available. We may update, pause, remove, or add features over time.",
      "To the fullest extent allowed by law, Captro is not responsible for user-generated content, offline interactions, service interruptions, lost data, or indirect damages. Some rights cannot be limited by law, so these limits apply only where legally permitted."
    ],
    bullets: []
  )
]

private let privacySections: [LegalSection] = [
  LegalSection(
    title: "Age and Children",
    paragraphs: [
      "Captro is for people who are at least 16 years old. Captro is not directed to children under 16, and we do not knowingly allow people under 16 to create accounts.",
      "If you believe a person under 16 created an account, contact support so we can review and take action."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Account and Identity Information",
    paragraphs: [
      "Captro collects information needed to create, protect, and manage your account."
    ],
    bullets: [
      "Username, display name, email address, authentication provider information, user ID, profile photo, bio, links, password credentials if you use email/password, and account status.",
      "Sign in with Apple or Google may provide identifiers, email address, name, or other login information according to your provider settings.",
      "Supabase Auth and Supabase Postgres may be used for authentication, account identity, profiles, structured app records, user settings, reports, moderation records, and other text or metadata."
    ]
  ),
  LegalSection(
    title: "Content You Create",
    paragraphs: [
      "Captro collects and processes content you create or choose to share so the app can work."
    ],
    bullets: [
      "Photos, story videos, captions, comments, profile details, bookmarks, saves, likes, follows, reports, moderation notes, and support requests.",
      "Messages and attachments you send in chat, including metadata such as sender, receiver, timestamps, delivery status, read status if used, and safety signals.",
      "Photos, videos, avatars, thumbnails, posters, and media processing records may be stored, optimized, resized, transcoded, scanned for safety, and delivered through Cloudflare services such as Cloudflare Workers, Cloudflare Images, R2, Stream, Queues, CDN, and Workers AI where configured."
    ]
  ),
  LegalSection(
    title: "Photos, Videos, Camera, Microphone, and Gallery",
    paragraphs: [
      "Captro asks for camera, microphone, and photo library permissions only when needed for features such as creating posts, recording stories, choosing media, editing media, saving edited media, and sending media in chat."
    ],
    bullets: [
      "Camera access is used to take photos for posts and record story videos.",
      "Microphone access is used when recording story videos or other media features that include audio.",
      "Photo library access is used to let you choose or save photos and videos. Captro does not need full-library access when a picker can provide selected media only."
    ]
  ),
  LegalSection(
    title: "Location and Check-In Data",
    paragraphs: [
      "Captro may offer two different location features: exact place tags and broad city/country labels. These are optional where available.",
      "Exact place tags can be selected through Apple MapKit or device place search. Broad city/country labels may be created from your profile city, manual selection, or approximate device location with permission. Mapbox may be used to turn approximate coordinates into a city/country label."
    ],
    bullets: [
      "Captro should not show your precise live location in Feed or Discover.",
      "If you turn on a city/country label, other users may see that broad label, such as New York, USA.",
      "If you add a place tag, other users may see that place name, such as a restaurant, park, cafe, venue, or gym.",
      "You can remove or hide location features where the app provides controls, and you can turn off device location permission in iOS Settings."
    ]
  ),
  LegalSection(
    title: "Device, Usage, Notifications, and Diagnostics",
    paragraphs: [
      "Captro may collect device and usage information to keep the app working, secure, and fast."
    ],
    bullets: [
      "Device type, operating system, app version, IP address, approximate network location, crash data, performance data, diagnostics, logs, security signals, and interaction data.",
      "Notification tokens and notification settings so Captro can send alerts for messages, comments, follows, reports, safety events, or other app activity if you allow notifications.",
      "Cache data may be stored on your device so Feed, Discover, profiles, chat, media previews, and settings can load faster."
    ]
  ),
  LegalSection(
    title: "How Captro Uses Information",
    paragraphs: [
      "Captro uses information to provide, protect, personalize, and improve the app."
    ],
    bullets: [
      "Create accounts, authenticate users, show Feed, Discover, profiles, stories, comments, chat, bookmarks, notifications, and settings.",
      "Upload, store, resize, transcode, optimize, cache, and deliver photos, videos, avatars, thumbnails, and posters through Cloudflare media services.",
      "Recommend or organize content, including Discover categories, search, profiles, and local cache behavior.",
      "Review reports, block abuse, enforce rules, prevent spam/scams, detect security issues, investigate policy violations, and comply with law.",
      "Improve reliability, media loading, app performance, user experience, and safety systems."
    ]
  ),
  LegalSection(
    title: "Sharing and Service Providers",
    paragraphs: [
      "Captro does not sell your personal information. Captro does not use your data for third-party advertising tracking unless that is disclosed and consent is obtained where required.",
      "Captro may share information only as needed to operate the app, protect users, comply with law, or support the service."
    ],
    bullets: [
      "With other users when you post, comment, share a profile, appear in Discover, send messages, like, save, follow, or use public app features.",
      "With service providers such as Supabase for authentication and structured Postgres data, Cloudflare for Worker API, media storage, media processing, CDN delivery, and safety jobs, Apple, Google, Mapbox, notification providers, analytics/diagnostics providers, moderation tools, and support tools where configured.",
      "With law enforcement, courts, regulators, or safety partners when required by law, legal process, emergency, abuse prevention, or protection of users and the public.",
      "If Captro is involved in a merger, sale, financing, acquisition, restructuring, or transfer of assets, information may transfer as part of that transaction."
    ]
  ),
  LegalSection(
    title: "Your Choices",
    paragraphs: [
      "You can control many parts of your data and experience."
    ],
    bullets: [
      "Update profile details, username, profile photo, privacy settings, and notification preferences where available.",
      "Use block, report, delete, hide, unsave, unfollow, or remove-place controls where available.",
      "Turn off camera, microphone, photos, notifications, or location permissions in iOS Settings.",
      "Clear local cache where the app provides a cache clearing control.",
      "Request account deletion in Settings or by contacting support."
    ]
  ),
  LegalSection(
    title: "Retention and Account Deletion",
    paragraphs: [
      "Captro keeps information for as long as needed to provide the app, protect users, comply with law, resolve disputes, prevent fraud, enforce rules, and maintain safety records.",
      "When you request deletion, Captro may place the account in a deletion-pending state, hide your profile and public content, log out sessions, delete push tokens, and permanently delete or anonymize eligible data after a 30-day deletion period. Some limited records may be kept for safety, security, legal, audit, or ban evasion reasons."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Security",
    paragraphs: [
      "Captro uses technical and organizational safeguards to protect account, media, chat, and safety information. No system is perfectly secure, so you should use a strong password, protect your device, and report suspicious activity."
    ],
    bullets: []
  )
]

private let communitySections: [LegalSection] = [
  LegalSection(
    title: "The Captro Standard",
    paragraphs: [
      "Captro is for real people, original photos, story videos, creativity, respectful comments, safer chat, useful Discover content, and genuine connection. Keep it human, honest, and safe."
    ],
    bullets: [
      "Use Captro only if you are at least 16 years old.",
      "Share content you created or have permission to share.",
      "Treat people with respect in comments, messages, profiles, stories, and Discover.",
      "Do not pressure people to respond, meet, send media, share private information, or send money."
    ]
  ),
  LegalSection(
    title: "Content and Behavior That Are Not Allowed",
    paragraphs: [
      "The following content and behavior may be removed and may lead to account limits, suspension, or permanent bans."
    ],
    bullets: [
      "Harassment, bullying, threats, hate speech, violent threats, gore, praise or support for violence, and dangerous behavior.",
      "Sexual exploitation, sexual solicitation, sexual content involving minors, grooming, coercion, non-consensual intimate media, and unwanted explicit content.",
      "Doxxing, private personal information, stalking, impersonation, scams, spam, fake engagement, stolen content, copyright violations, illegal activity, malware, phishing, and ban evasion.",
      "Content that promotes self-harm, suicide, eating disorder harm, dangerous challenges, or instructions for serious harm.",
      "Abuse of reporting, blocking, moderation, location, chat, upload, or safety tools."
    ]
  ),
  LegalSection(
    title: "Chat Rules",
    paragraphs: [
      "Private messages must follow the same safety standards as public areas. Chat should never be used to pressure, threaten, exploit, stalk, or scam people."
    ],
    bullets: [
      "No harassment, threats, unwanted explicit content, sexual exploitation, scams, spam, coercion, or requests for money from strangers.",
      "Do not share another person's private personal information, private photos, documents, address, phone number, or financial details.",
      "If a message makes you uncomfortable, block and report the user where available."
    ]
  ),
  LegalSection(
    title: "Posts, Discover, Profiles, and Stories",
    paragraphs: [
      "Posts, Discover content, profile grids, comments, stories, media previews, bookmarks, and location/place tags must follow these Guidelines."
    ],
    bullets: [
      "No stolen images or videos.",
      "No misleading content, spam galleries, unsafe content, abusive content, or manipulated engagement.",
      "Use captions, tags, categories, places, and city/country labels honestly and respectfully.",
      "Do not use exact place tags or broad location labels to expose someone's private location."
    ]
  ),
  LegalSection(
    title: "AI, Editing, and Authenticity",
    paragraphs: [
      "Captro may use automated tools to help categorize Discover content, improve captions, moderate uploads, or protect safety. Do not use editing tools, AI-generated media, or misleading captions to impersonate people, deceive users, exploit others, or evade moderation."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Enforcement",
    paragraphs: [
      "Captro may use warnings, content removal, reduced visibility, feature limits, account suspension, permanent bans, deletion of unsafe media, and device, IP, identity, or behavior-based ban evasion review where available."
    ],
    bullets: []
  )
]

private let safetySections: [LegalSection] = [
  LegalSection(
    title: "Age and Safety",
    paragraphs: [
      "Captro is for people 16 and older. If you are under 16, do not use Captro. If you believe someone under 16 is using Captro, report it or contact support."
    ],
    bullets: []
  ),
  LegalSection(
    title: "How to Report",
    paragraphs: [
      "Use in-app reporting tools where available to report posts, comments, profiles, messages, chat conversations, stories, Discover posts, bookmarks, places, or other unsafe activity."
    ],
    bullets: [
      "Choose the closest report reason and include helpful context when the app allows it.",
      "The reported user should not be told who reported them by Captro.",
      "For urgent support or account issues, contact karfalacisse900@gmail.com."
    ]
  ),
  LegalSection(
    title: "Blocking",
    paragraphs: [
      "Blocking helps stop unwanted interaction where supported. Depending on app behavior, blocked users may be limited from messaging, commenting, or viewing certain profile activity."
    ],
    bullets: []
  ),
  LegalSection(
    title: "After a Report",
    paragraphs: [
      "Reports may be reviewed through automated systems, moderation/admin tools, or human reviewers. Captro may remove content, warn users, limit features, suspend accounts, ban accounts, or preserve safety records. Reports may not always receive individual responses.",
      "If there is immediate danger, contact local emergency services first. Captro is not an emergency service."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Personal Safety Advice",
    paragraphs: [
      "Be careful with what you share and who you trust online."
    ],
    bullets: [
      "Do not share your personal address, phone number, financial information, private photos, sensitive documents, passwords, or verification codes.",
      "Be careful meeting people from chat. If you meet someone offline, meet in public, tell someone you trust, and leave if you feel unsafe.",
      "Do not send money to strangers.",
      "Report threats, harassment, scams, doxxing, exploitation, stalking, or coercive behavior."
    ]
  ),
  LegalSection(
    title: "Chat Safety",
    paragraphs: [
      "You can report messages and block abusive users where supported. Captro may review reported messages or safety-related content when necessary to investigate reports, enforce policies, protect users, or comply with law."
    ],
    bullets: [
      "Do not share passwords, verification codes, private documents, money details, your address, or live location.",
      "Be careful meeting people from the app. Meet in public, tell someone you trust, and leave if you feel unsafe.",
      "Never send money to strangers or people pressuring you in chat."
    ]
  ),
  LegalSection(
    title: "Location Safety",
    paragraphs: [
      "Location and place features can be useful, but they can also create risk. Only share a place, city, or country when you are comfortable with other users seeing it."
    ],
    bullets: [
      "Do not tag a private home, school, workplace, or sensitive location unless it is safe and appropriate.",
      "Do not reveal another person's location without permission.",
      "Turn off location permission in iOS Settings if you do not want Captro to access location."
    ]
  )
]
