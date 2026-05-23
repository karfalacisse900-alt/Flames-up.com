import SwiftUI

private let captroLegalLastUpdated = "May 23, 2026"
private let captroSupportEmail = "karfalacisse900@gmail.com"
private let captroWebsiteDomain = "[insert domain, for example captro.app or getcaptro.com]"
private let captroLegalDisclaimer = "These pages are provided for general information and should be reviewed by a qualified legal professional before public launch."

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
      "Captro is a social media, photo, and short-video sharing app for capturing moments, posting photos and videos, discovering visual content, and connecting with people through profiles, chat, feed posts, stories, fullscreen media, notifications, and gallery-style discovery.",
      "These Terms explain the rules for using Captro. If you do not agree, do not use the app."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Eligibility and Accounts",
    paragraphs: [
      "You must be at least 13 years old, or the minimum age required in your country if higher, to use Captro. If you are under the age of majority where you live, you should use Captro only with permission from a parent or guardian.",
      "You are responsible for your account, login credentials, profile details, username, and activity. Keep your password private and tell us if you believe your account has been accessed without permission."
    ],
    bullets: [
      "Usernames, display names, profile photos, bios, and links must not impersonate others, mislead people, promote hate, or violate another person's rights.",
      "You may not sell, transfer, automate, or misuse an account in a way that harms Captro or other users."
    ]
  ),
  LegalSection(
    title: "User Content and License",
    paragraphs: [
      "You own the photos, videos, captions, comments, messages, profile information, stories, gallery posts, and other content you create or upload, subject to any rights held by others.",
      "To operate Captro, you give Captro permission to host, store, process, resize, transcode, display, distribute inside the app, moderate, and otherwise use your content only as needed to provide, improve, protect, and promote Captro features."
    ],
    bullets: [
      "Public or shared content such as feed posts, profile posts, Discover posts, gallery posts, stories, comments, likes, saves, shares, and profile details may be visible to other users depending on app settings and feature behavior.",
      "Private chat messages are not public posts. They may still be processed to deliver the service, enforce safety rules, investigate reports, prevent abuse, or comply with law.",
      "Do not upload photos, videos, music, captions, screenshots, or other content unless you own it or have permission to use it."
    ]
  ),
  LegalSection(
    title: "Prohibited Content and Behavior",
    paragraphs: [
      "You may not use Captro to harm people, abuse the platform, or violate the law. Captro may remove content, limit features, suspend accounts, or ban accounts when these rules are violated."
    ],
    bullets: [
      "No harassment, bullying, threats, hate speech, violence, incitement, exploitation, sexual content involving minors, doxxing, stalking, or sharing private personal information.",
      "No scams, spam, fake engagement, impersonation, stolen content, copyright violations, illegal activity, dangerous behavior, ban evasion, or attempts to bypass safety systems.",
      "Do not use chat to harass, threaten, scam, spam, exploit, pressure, send unwanted explicit content, ask for money, coerce, or share private information.",
      "Do not use location, place, or check-in features to stalk, expose, threaten, harass, or mislead people about another person's location."
    ]
  ),
  LegalSection(
    title: "Reporting, Blocking, and Moderation",
    paragraphs: [
      "Captro may provide reporting, blocking, moderation, and admin review tools. Reports may be reviewed by moderation systems, admins, or service providers helping us keep the app safe.",
      "Captro may remove or restrict posts, comments, profiles, stories, Discover content, gallery content, messages, places, or accounts. Captro may also suspend or remove accounts, preserve safety records, and review ban evasion."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Copyright, Availability, and Changes",
    paragraphs: [
      "Respect copyright and intellectual property rights. If you believe content infringes your rights, contact support with enough detail for us to review it.",
      "Captro is provided as available. We do not guarantee uninterrupted access, error-free service, or that every feature will remain available. Features may change, be removed, or be added over time."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Liability and Terms Changes",
    paragraphs: [
      "To the fullest extent allowed by law, Captro is not responsible for user-generated content, offline interactions, service interruptions, lost data, or indirect damages. Some rights cannot be limited by law, so these limits apply only where legally permitted.",
      "We may update these Terms. If changes are material, we may provide notice in the app or by another reasonable method. Continued use of Captro after changes means you accept the updated Terms."
    ],
    bullets: []
  )
]

private let privacySections: [LegalSection] = [
  LegalSection(
    title: "Information You Provide",
    paragraphs: [
      "Captro may collect information you provide when creating or using an account, communicating with other users, posting media, reporting content, or contacting support."
    ],
    bullets: [
      "Name or display name, username, email address, password or login credentials, profile photo, bio, links, and account details.",
      "Posts, photos, videos, captions, comments, likes, saves, follows or friends, reports, support messages, and other activity you choose to create."
    ]
  ),
  LegalSection(
    title: "Chat and Message Data",
    paragraphs: [
      "Captro processes messages you send and receive so private chat can work. Private messages are not public posts, but they may be processed to provide the service, enforce safety, investigate reports, prevent abuse, or comply with law."
    ],
    bullets: [
      "Message content and attachments.",
      "Message metadata such as sender, receiver, timestamps, delivery status, read status if used, and safety signals."
    ]
  ),
  LegalSection(
    title: "Discover, Gallery, Stories, and Media Data",
    paragraphs: [
      "Captro may process posts shown in Feed, Discover, profile grids, stories, fullscreen viewers, and gallery-style surfaces. We may generate thumbnails, previews, optimized feed versions, and playback versions while preserving the original upload when technically possible."
    ],
    bullets: [
      "Views, interactions, likes, saves, comments, shares, reports, and other usage activity may be used to operate and improve the app.",
      "Public content may be visible to other users. Do not post private information you do not want others to see."
    ]
  ),
  LegalSection(
    title: "Location and Check-In Data",
    paragraphs: [
      "If Captro offers location, place, nearby, or check-in features, we may process approximate location, precise location with permission, place tags, check-ins, and related content.",
      "You can control camera, photos, microphone, notifications, and location permissions in your device settings."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Device, Technical, and Usage Data",
    paragraphs: [
      "Captro may collect device type, operating system, app version, IP address, log data, crash reports, performance data, security signals, and usage activity."
    ],
    bullets: [
      "We use this information to keep Captro reliable, secure, and smooth.",
      "We may use logs and security signals to detect spam, abuse, scams, fraud, ban evasion, and unauthorized access."
    ]
  ),
  LegalSection(
    title: "How Information Is Used",
    paragraphs: [
      "Captro uses information to create and manage accounts, show Feed, Profile, Discover, chat, stories, posts, comments, notifications, gallery content, and support requests."
    ],
    bullets: [
      "Improve app performance, media quality, loading states, safety, moderation, recommendations, and user experience.",
      "Detect and respond to spam, abuse, scams, fraud, security issues, policy violations, and legal obligations."
    ]
  ),
  LegalSection(
    title: "How Information Is Shared",
    paragraphs: [
      "We do not sell personal information. Information may be shared when needed to operate the app, comply with law, keep people safe, or complete a business transfer if applicable."
    ],
    bullets: [
      "With other users when your content, profile, comments, stories, posts, or interactions are public or shared through app features.",
      "With service providers for hosting, storage, analytics, maps, notifications, media processing, security, support, and moderation.",
      "If required by law, legal process, safety needs, or to protect Captro, users, or the public."
    ]
  ),
  LegalSection(
    title: "Deletion, Retention, and Choices",
    paragraphs: [
      "You can request account deletion through the app if available or by contacting support at karfalacisse900@gmail.com. Some information may be retained when needed for safety, security, fraud prevention, legal compliance, dispute resolution, or moderation records.",
      "You can update profile information in the app and control device permissions such as camera, photos, microphone, notifications, and location from device settings."
    ],
    bullets: []
  )
]

private let communitySections: [LegalSection] = [
  LegalSection(
    title: "The Captro Culture",
    paragraphs: [
      "Captro is for real people, original photos and videos, captured moments, creativity, respectful comments, safe messaging, useful Discover and gallery content, and genuine connection."
    ],
    bullets: [
      "Share content you created or have permission to share.",
      "Treat people with respect in comments, messages, profiles, stories, and Discover.",
      "Avoid spammy, stolen, fake, or misleading content."
    ]
  ),
  LegalSection(
    title: "Content That Is Not Allowed",
    paragraphs: [
      "The following content and behavior may be removed and may lead to account limits, suspension, or permanent bans."
    ],
    bullets: [
      "Harassment, bullying, threats, hate speech, violence, incitement, sexual exploitation, sexual content involving minors, and dangerous behavior.",
      "Doxxing, private personal information, stalking, impersonation, scams, spam, fake engagement, stolen content, copyright violations, illegal activity, and ban evasion.",
      "Abuse of reporting, blocking, moderation, or safety tools."
    ]
  ),
  LegalSection(
    title: "Chat Rules",
    paragraphs: [
      "Private messages must follow the same safety standards as public areas. Chat should never be used to pressure, threaten, exploit, stalk, or scam people."
    ],
    bullets: [
      "No harassment, threats, unwanted explicit content, sexual exploitation, scams, spam, coercion, or requests for money from strangers.",
      "Do not share another person's private personal information, private photos, documents, address, phone number, or financial details."
    ]
  ),
  LegalSection(
    title: "Discover, Gallery, Feed, and Stories",
    paragraphs: [
      "Discover posts, gallery-style visual content, feed posts, stories, profile grids, comments, and fullscreen media must follow these Guidelines."
    ],
    bullets: [
      "No stolen images or videos.",
      "No misleading content, spam galleries, unsafe content, abusive content, or manipulated engagement.",
      "Use captions, tags, and locations honestly and respectfully."
    ]
  ),
  LegalSection(
    title: "Location and Check-In Safety",
    paragraphs: [
      "If location, place, or check-in features are available, use them safely. Do not expose someone else's private location, stalk or follow people, fake harmful location claims, or use places/check-ins to harass businesses or people."
    ],
    bullets: []
  ),
  LegalSection(
    title: "Enforcement",
    paragraphs: [
      "Captro may use warnings, content removal, feature limits, account suspension, permanent bans, and device, IP, or behavior-based ban evasion review where available."
    ],
    bullets: []
  )
]

private let safetySections: [LegalSection] = [
  LegalSection(
    title: "How to Report",
    paragraphs: [
      "Use in-app reporting tools where available to report posts, comments, profiles, messages, chat conversations, stories, Discover posts, gallery posts, check-ins, places, or other unsafe activity."
    ],
    bullets: [
      "Choose the closest report reason and include helpful context when the app allows it.",
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
      "Reports may be reviewed through moderation/admin tools. Captro may remove content, warn users, limit features, suspend accounts, or ban accounts. Reports may not always receive individual responses.",
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
    bullets: []
  )
]
