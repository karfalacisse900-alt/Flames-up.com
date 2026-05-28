import Foundation
import Combine

public enum MIRAAppLanguage: String, CaseIterable, Identifiable {
  case system
  case english = "en"
  case french = "fr"
  case spanish = "es"

  public var id: String { rawValue }
}

public enum MIRALanguageResolver {
  public static let preferenceKey = "captro.language.preference"
  private static let supported = ["en", "fr", "es"]

  public static func storedPreference() -> String {
    let value = UserDefaults.standard.string(forKey: preferenceKey) ?? MIRAAppLanguage.system.rawValue
    return value == "system" || supported.contains(value) ? value : MIRAAppLanguage.system.rawValue
  }

  public static func resolvedLanguageCode(for preference: String? = nil) -> String {
    let value = preference ?? storedPreference()
    if supported.contains(value) { return value }
    let systemCode = Locale.preferredLanguages.first?
      .split(separator: "-")
      .first
      .map(String.init)?
      .lowercased() ?? "en"
    return supported.contains(systemCode) ? systemCode : "en"
  }

  public static func acceptLanguageHeader() -> String {
    let language = resolvedLanguageCode()
    return "\(language), en;q=0.8"
  }

  static func localizedAPIError(code: String?) -> String {
    let key: String
    switch code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "username_taken", "taken": key = "error.username_taken"
    case "username_invalid", "invalid_username", "too_short", "too_long", "invalid_format", "reserved", "blocked_word": key = "error.username_invalid"
    case "post_not_found", "not_found": key = "error.post_not_found"
    case "target_not_found": key = "error.target_not_found"
    case "unauthorized": key = "error.unauthorized"
    case "upload_failed": key = "error.upload_failed"
    case "report_duplicate": key = "error.report_duplicate"
    case "rate_limited": key = "error.rate_limited"
    default: key = "error.generic"
    }
    return MIRALocalizationTable.value(for: key, language: resolvedLanguageCode())
  }
}

public final class MIRALocalization: ObservableObject {
  public static let shared = MIRALocalization()

  @Published public private(set) var preference: MIRAAppLanguage

  public var resolvedLanguageCode: String {
    MIRALanguageResolver.resolvedLanguageCode(for: preference.rawValue)
  }

  private init() {
    preference = MIRAAppLanguage(rawValue: MIRALanguageResolver.storedPreference()) ?? .system
  }

  public func setPreference(_ rawValue: String) {
    let next = MIRAAppLanguage(rawValue: rawValue) ?? .system
    guard next != preference else { return }
    preference = next
    UserDefaults.standard.set(next.rawValue, forKey: MIRALanguageResolver.preferenceKey)
  }

  public func string(_ key: String) -> String {
    MIRALocalizationTable.value(for: key, language: resolvedLanguageCode)
  }

  public func discoverCategoryLabel(_ slug: String) -> String {
    string("discover.category.\(slug)")
  }

  public func reportReasonLabel(_ slug: String) -> String {
    string("report.reason.\(slug)")
  }

  public func languageDisplayName(_ rawValue: String) -> String {
    switch rawValue {
    case MIRAAppLanguage.system.rawValue: return string("settings.system_default")
    case MIRAAppLanguage.english.rawValue: return "English"
    case MIRAAppLanguage.french.rawValue: return "Français"
    case MIRAAppLanguage.spanish.rawValue: return "Español"
    default: return "English"
    }
  }
}

private enum MIRALocalizationTable {
  private static let values: [String: [String: String]] = [
    "en": [
      "common.cancel": "Cancel",
      "common.done": "Done",
      "common.retry": "Retry",
      "common.loading": "Loading",
      "common.error": "Something went wrong.",
      "common.close": "Close",
      "common.back": "Back",
      "common.save": "Save",
      "common.saving": "Saving...",
      "common.delete": "Delete",
      "common.report": "Report",
      "common.block_user": "Block user",
      "common.unblock": "Unblock",
      "common.not_interested": "Not interested",
      "common.share": "Share",
      "auth.login": "Log in",
      "auth.signup": "Sign up",
      "auth.continue": "Continue",
      "auth.choose_username": "Choose your username",
      "auth.username_subtitle": "This is how people will find you on Captro.",
      "auth.username_placeholder": "username",
      "auth.username_helper": "3-20 characters. Letters, numbers, underscores, and periods only.",
      "auth.username_checking": "Checking...",
      "auth.username_available": "Username available",
      "auth.username_taken": "Username already taken",
      "auth.username_check_failed": "Could not check that username. Try again.",
      "auth.username_save_failed": "Could not save username. Try another one.",
      "auth.username_suggestions": "Suggestions",
      "auth.username_too_short": "Username must be at least 3 characters.",
      "auth.username_too_long": "Username must be 20 characters or fewer.",
      "auth.username_format": "Use only letters, numbers, underscores, and periods.",
      "auth.username_period_rule": "Username cannot start or end with a period or contain double periods.",
      "auth.username_cannot_use": "Username cannot be used.",
      "welcome.capture.title": "Capture\nyour moment",
      "welcome.capture.subtitle": "Share photos and short videos that feel real, not fake.",
      "welcome.discover.title": "Discover\nyour world",
      "welcome.discover.subtitle": "Explore photography, outfits, food, outdoors, events, and more.",
      "welcome.people.title": "Find\nyour people",
      "welcome.people.subtitle": "Connect through what you post, what you love, and what you discover.",
      "feed.title": "Home",
      "feed.empty.title": "No posts yet",
      "feed.empty.message": "Fresh moments will show here when they are ready.",
      "discover.title": "Discover",
      "discover.empty.title": "Nothing here yet",
      "discover.empty.message": "Try another category or check back soon.",
      "discover.category.all": "All",
      "discover.category.photography": "Photography",
      "discover.category.outdoors": "Outdoors",
      "discover.category.outfits": "Outfits",
      "discover.category.food": "Food",
      "discover.category.travel": "Travel",
      "discover.category.events": "Events",
      "discover.category.nightlife": "Nightlife",
      "discover.category.art": "Art",
      "discover.category.lifestyle": "Lifestyle",
      "discover.category.fitness": "Fitness",
      "discover.category.pets": "Pets",
      "discover.category.cars": "Cars",
      "discover.category.beauty": "Beauty",
      "profile.title": "Profile",
      "chat.title": "Chat",
      "comments.title": "Comments",
      "comments.empty.title": "No comments yet",
      "comments.empty.message": "Start the conversation.",
      "comments.add_placeholder": "Add a comment...",
      "comments.reply_placeholder": "Write a reply...",
      "post.create.title": "Create post",
      "camera.title": "Camera",
      "upload.loading": "Uploading...",
      "upload.failed": "Upload failed. Please try again.",
      "report.title": "Report",
      "report.subtitle": "Help us understand what happened.",
      "report.details.title": "Add details",
      "report.details.body": "You can add more information to help us review this report.",
      "report.details.placeholder": "Add details...",
      "report.submit": "Submit report",
      "report.submit_and_block": "Submit and block user",
      "report.submitted": "Report submitted",
      "report.submitted.body": "Thanks for helping keep Captro safe. We’ll review this and take action if it breaks our rules.",
      "report.failed": "Couldn’t submit report. Please try again.",
      "report.duplicate": "You already reported this. Thanks — we’re reviewing it.",
      "report.blocked": "You blocked this user. They won’t be able to message you.",
      "report.hide_content": "Hide this content",
      "report.reason.harassment": "Harassment or bullying",
      "report.reason.hate_speech": "Hate speech",
      "report.reason.threats_violence": "Threats or violence",
      "report.reason.doxxing_private_info": "Doxxing or private information",
      "report.reason.spam_scam": "Spam or scam",
      "report.reason.impersonation": "Impersonation",
      "report.reason.stolen_content": "Stolen content or copyright",
      "report.reason.sexual_exploitation": "Sexual content or exploitation",
      "report.reason.illegal_dangerous_activity": "Illegal or dangerous activity",
      "report.reason.self_harm": "Self-harm concern",
      "report.reason.misleading_content": "False or misleading content",
      "report.reason.dont_want_to_see": "I don’t want to see this",
      "report.reason.other": "Other",
      "settings.title": "Settings",
      "settings.account": "Account",
      "settings.preferences": "Preferences",
      "settings.language": "App Language",
      "settings.system_default": "System Default",
      "settings.language_updated": "Language updated. Restart Captro to apply language change everywhere.",
      "settings.language_failed": "Could not update language.",
      "settings.privacy": "Privacy",
      "settings.notifications": "Notifications",
      "settings.security": "Security",
      "settings.app_permissions": "App permissions",
      "settings.legal_safety": "Legal & Safety",
      "settings.support": "Support",
      "settings.manage_account": "Manage your account",
      "settings.restart_to_apply": "Restart Captro to apply language change.",
      "legal.terms": "Terms of Service",
      "legal.privacy": "Privacy Policy",
      "legal.community": "Community Guidelines",
      "legal.safety": "Safety & Reporting",
      "ugc.see_translation": "See translation",
      "ugc.view_original": "View original",
      "notification.like": "%@ liked your post.",
      "notification.comment": "%@ commented on your post.",
      "notification.message": "New message from %@",
      "error.username_taken": "Username is already taken.",
      "error.username_invalid": "Choose a valid username.",
      "error.post_not_found": "Post was not found.",
      "error.target_not_found": "We could not find that content.",
      "error.unauthorized": "Please log in again.",
      "error.upload_failed": "Upload failed. Please try again.",
      "error.report_duplicate": "You already reported this.",
      "error.rate_limited": "Too many attempts. Try again soon.",
      "error.generic": "The server could not finish this request."
    ],
    "fr": [
      "common.cancel": "Annuler",
      "common.done": "Terminé",
      "common.retry": "Réessayer",
      "common.loading": "Chargement",
      "common.error": "Une erreur s’est produite.",
      "common.close": "Fermer",
      "common.back": "Retour",
      "common.save": "Enregistrer",
      "common.saving": "Enregistrement...",
      "common.delete": "Supprimer",
      "common.report": "Signaler",
      "common.block_user": "Bloquer l’utilisateur",
      "common.unblock": "Débloquer",
      "common.not_interested": "Pas intéressé",
      "common.share": "Partager",
      "auth.login": "Connexion",
      "auth.signup": "S’inscrire",
      "auth.continue": "Continuer",
      "auth.choose_username": "Choisissez votre nom d’utilisateur",
      "auth.username_subtitle": "C’est ainsi que les gens vous trouveront sur Captro.",
      "auth.username_placeholder": "nom_utilisateur",
      "auth.username_helper": "3 à 20 caractères. Lettres, chiffres, traits bas et points uniquement.",
      "auth.username_checking": "Vérification...",
      "auth.username_available": "Nom d’utilisateur disponible",
      "auth.username_taken": "Nom d’utilisateur déjà pris",
      "auth.username_check_failed": "Impossible de vérifier ce nom. Réessayez.",
      "auth.username_save_failed": "Impossible d’enregistrer ce nom. Essayez-en un autre.",
      "auth.username_suggestions": "Suggestions",
      "auth.username_too_short": "Le nom doit contenir au moins 3 caractères.",
      "auth.username_too_long": "Le nom doit contenir 20 caractères ou moins.",
      "auth.username_format": "Utilisez uniquement des lettres, chiffres, traits bas et points.",
      "auth.username_period_rule": "Le nom ne peut pas commencer ou finir par un point ni contenir deux points.",
      "auth.username_cannot_use": "Ce nom d’utilisateur ne peut pas être utilisé.",
      "welcome.capture.title": "Capturez\nvotre moment",
      "welcome.capture.subtitle": "Partagez des photos et de courtes vidéos qui semblent vraies, pas fausses.",
      "welcome.discover.title": "Découvrez\nvotre monde",
      "welcome.discover.subtitle": "Explorez la photographie, les tenues, la nourriture, l’extérieur, les événements et plus encore.",
      "welcome.people.title": "Trouvez\nvos personnes",
      "welcome.people.subtitle": "Connectez-vous grâce à ce que vous publiez, aimez et découvrez.",
      "feed.title": "Accueil",
      "feed.empty.title": "Aucune publication",
      "feed.empty.message": "Les nouveaux moments apparaîtront ici dès qu’ils seront prêts.",
      "discover.title": "Découvrir",
      "discover.empty.title": "Rien ici pour l’instant",
      "discover.empty.message": "Essayez une autre catégorie ou revenez bientôt.",
      "discover.category.all": "Tout",
      "discover.category.photography": "Photographie",
      "discover.category.outdoors": "Extérieur",
      "discover.category.outfits": "Tenues",
      "discover.category.food": "Nourriture",
      "discover.category.travel": "Voyage",
      "discover.category.events": "Événements",
      "discover.category.nightlife": "Vie nocturne",
      "discover.category.art": "Art",
      "discover.category.lifestyle": "Style de vie",
      "discover.category.fitness": "Fitness",
      "discover.category.pets": "Animaux",
      "discover.category.cars": "Voitures",
      "discover.category.beauty": "Beauté",
      "profile.title": "Profil",
      "chat.title": "Chat",
      "comments.title": "Commentaires",
      "comments.empty.title": "Aucun commentaire",
      "comments.empty.message": "Lancez la conversation.",
      "comments.add_placeholder": "Ajouter un commentaire...",
      "comments.reply_placeholder": "Écrire une réponse...",
      "post.create.title": "Créer une publication",
      "camera.title": "Caméra",
      "upload.loading": "Téléversement...",
      "upload.failed": "Échec du téléversement. Réessayez.",
      "report.title": "Signaler",
      "report.subtitle": "Aidez-nous à comprendre ce qui s’est passé.",
      "report.details.title": "Ajouter des détails",
      "report.details.body": "Vous pouvez ajouter des informations pour nous aider à examiner ce signalement.",
      "report.details.placeholder": "Ajouter des détails...",
      "report.submit": "Envoyer le signalement",
      "report.submit_and_block": "Signaler et bloquer l’utilisateur",
      "report.submitted": "Signalement envoyé",
      "report.submitted.body": "Merci d’aider à garder Captro sûr. Nous examinerons ce contenu et agirons s’il enfreint nos règles.",
      "report.failed": "Impossible d’envoyer le signalement. Réessayez.",
      "report.duplicate": "Vous avez déjà signalé cela. Merci — nous l’examinons.",
      "report.blocked": "Vous avez bloqué cet utilisateur. Il ne pourra pas vous envoyer de messages.",
      "report.hide_content": "Masquer ce contenu",
      "report.reason.harassment": "Harcèlement ou intimidation",
      "report.reason.hate_speech": "Discours haineux",
      "report.reason.threats_violence": "Menaces ou violence",
      "report.reason.doxxing_private_info": "Doxxing ou informations privées",
      "report.reason.spam_scam": "Spam ou arnaque",
      "report.reason.impersonation": "Usurpation d’identité",
      "report.reason.stolen_content": "Contenu volé ou droit d’auteur",
      "report.reason.sexual_exploitation": "Contenu sexuel ou exploitation",
      "report.reason.illegal_dangerous_activity": "Activité illégale ou dangereuse",
      "report.reason.self_harm": "Préoccupation d’automutilation",
      "report.reason.misleading_content": "Contenu faux ou trompeur",
      "report.reason.dont_want_to_see": "Je ne veux pas voir cela",
      "report.reason.other": "Autre",
      "settings.title": "Réglages",
      "settings.account": "Compte",
      "settings.preferences": "Préférences",
      "settings.language": "Langue de l’app",
      "settings.system_default": "Langue du système",
      "settings.language_updated": "Langue mise à jour. Redémarrez Captro pour l’appliquer partout.",
      "settings.language_failed": "Impossible de mettre à jour la langue.",
      "settings.privacy": "Confidentialité",
      "settings.notifications": "Notifications",
      "settings.security": "Sécurité",
      "settings.app_permissions": "Autorisations de l’app",
      "settings.legal_safety": "Légal et sécurité",
      "settings.support": "Assistance",
      "settings.manage_account": "Gérer votre compte",
      "settings.restart_to_apply": "Redémarrez Captro pour appliquer la langue.",
      "legal.terms": "Conditions d’utilisation",
      "legal.privacy": "Politique de confidentialité",
      "legal.community": "Règles de la communauté",
      "legal.safety": "Sécurité et signalement",
      "ugc.see_translation": "Voir la traduction",
      "ugc.view_original": "Voir l’original",
      "notification.like": "%@ a aimé votre publication.",
      "notification.comment": "%@ a commenté votre publication.",
      "notification.message": "Nouveau message de %@",
      "error.username_taken": "Ce nom d’utilisateur est déjà pris.",
      "error.username_invalid": "Choisissez un nom d’utilisateur valide.",
      "error.post_not_found": "Publication introuvable.",
      "error.target_not_found": "Nous n’avons pas trouvé ce contenu.",
      "error.unauthorized": "Veuillez vous reconnecter.",
      "error.upload_failed": "Échec du téléversement. Réessayez.",
      "error.report_duplicate": "Vous avez déjà signalé cela.",
      "error.rate_limited": "Trop de tentatives. Réessayez bientôt.",
      "error.generic": "Le serveur n’a pas pu terminer cette demande."
    ],
    "es": [
      "common.cancel": "Cancelar",
      "common.done": "Listo",
      "common.retry": "Reintentar",
      "common.loading": "Cargando",
      "common.error": "Algo salió mal.",
      "common.close": "Cerrar",
      "common.back": "Atrás",
      "common.save": "Guardar",
      "common.saving": "Guardando...",
      "common.delete": "Eliminar",
      "common.report": "Reportar",
      "common.block_user": "Bloquear usuario",
      "common.unblock": "Desbloquear",
      "common.not_interested": "No me interesa",
      "common.share": "Compartir",
      "auth.login": "Iniciar sesión",
      "auth.signup": "Registrarse",
      "auth.continue": "Continuar",
      "auth.choose_username": "Elige tu nombre de usuario",
      "auth.username_subtitle": "Así es como la gente te encontrará en Captro.",
      "auth.username_placeholder": "usuario",
      "auth.username_helper": "3-20 caracteres. Solo letras, números, guiones bajos y puntos.",
      "auth.username_checking": "Comprobando...",
      "auth.username_available": "Nombre de usuario disponible",
      "auth.username_taken": "Nombre de usuario ya en uso",
      "auth.username_check_failed": "No se pudo comprobar ese nombre. Inténtalo de nuevo.",
      "auth.username_save_failed": "No se pudo guardar el nombre. Prueba otro.",
      "auth.username_suggestions": "Sugerencias",
      "auth.username_too_short": "El nombre debe tener al menos 3 caracteres.",
      "auth.username_too_long": "El nombre debe tener 20 caracteres o menos.",
      "auth.username_format": "Usa solo letras, números, guiones bajos y puntos.",
      "auth.username_period_rule": "El nombre no puede empezar o terminar con punto ni contener puntos dobles.",
      "auth.username_cannot_use": "Ese nombre de usuario no se puede usar.",
      "welcome.capture.title": "Captura\ntu momento",
      "welcome.capture.subtitle": "Comparte fotos y videos cortos que se sientan reales, no falsos.",
      "welcome.discover.title": "Descubre\ntu mundo",
      "welcome.discover.subtitle": "Explora fotografía, outfits, comida, aire libre, eventos y más.",
      "welcome.people.title": "Encuentra\ntu gente",
      "welcome.people.subtitle": "Conecta por lo que publicas, lo que amas y lo que descubres.",
      "feed.title": "Inicio",
      "feed.empty.title": "Aún no hay publicaciones",
      "feed.empty.message": "Los nuevos momentos aparecerán aquí cuando estén listos.",
      "discover.title": "Descubrir",
      "discover.empty.title": "Nada aquí todavía",
      "discover.empty.message": "Prueba otra categoría o vuelve pronto.",
      "discover.category.all": "Todo",
      "discover.category.photography": "Fotografía",
      "discover.category.outdoors": "Aire libre",
      "discover.category.outfits": "Outfits",
      "discover.category.food": "Comida",
      "discover.category.travel": "Viajes",
      "discover.category.events": "Eventos",
      "discover.category.nightlife": "Vida nocturna",
      "discover.category.art": "Arte",
      "discover.category.lifestyle": "Estilo de vida",
      "discover.category.fitness": "Fitness",
      "discover.category.pets": "Mascotas",
      "discover.category.cars": "Autos",
      "discover.category.beauty": "Belleza",
      "profile.title": "Perfil",
      "chat.title": "Chat",
      "comments.title": "Comentarios",
      "comments.empty.title": "Aún no hay comentarios",
      "comments.empty.message": "Empieza la conversación.",
      "comments.add_placeholder": "Agrega un comentario...",
      "comments.reply_placeholder": "Escribe una respuesta...",
      "post.create.title": "Crear publicación",
      "camera.title": "Cámara",
      "upload.loading": "Subiendo...",
      "upload.failed": "No se pudo subir. Inténtalo de nuevo.",
      "report.title": "Reportar",
      "report.subtitle": "Ayúdanos a entender qué pasó.",
      "report.details.title": "Agregar detalles",
      "report.details.body": "Puedes agregar más información para ayudarnos a revisar este reporte.",
      "report.details.placeholder": "Agregar detalles...",
      "report.submit": "Enviar reporte",
      "report.submit_and_block": "Reportar y bloquear usuario",
      "report.submitted": "Reporte enviado",
      "report.submitted.body": "Gracias por ayudar a mantener Captro seguro. Revisaremos esto y tomaremos medidas si rompe nuestras reglas.",
      "report.failed": "No se pudo enviar el reporte. Inténtalo de nuevo.",
      "report.duplicate": "Ya reportaste esto. Gracias, lo estamos revisando.",
      "report.blocked": "Bloqueaste a este usuario. No podrá enviarte mensajes.",
      "report.hide_content": "Ocultar este contenido",
      "report.reason.harassment": "Acoso o bullying",
      "report.reason.hate_speech": "Discurso de odio",
      "report.reason.threats_violence": "Amenazas o violencia",
      "report.reason.doxxing_private_info": "Doxxing o información privada",
      "report.reason.spam_scam": "Spam o estafa",
      "report.reason.impersonation": "Suplantación",
      "report.reason.stolen_content": "Contenido robado o copyright",
      "report.reason.sexual_exploitation": "Contenido sexual o explotación",
      "report.reason.illegal_dangerous_activity": "Actividad ilegal o peligrosa",
      "report.reason.self_harm": "Riesgo de autolesión",
      "report.reason.misleading_content": "Contenido falso o engañoso",
      "report.reason.dont_want_to_see": "No quiero ver esto",
      "report.reason.other": "Otro",
      "settings.title": "Configuración",
      "settings.account": "Cuenta",
      "settings.preferences": "Preferencias",
      "settings.language": "Idioma de la app",
      "settings.system_default": "Predeterminado del sistema",
      "settings.language_updated": "Idioma actualizado. Reinicia Captro para aplicarlo en todas partes.",
      "settings.language_failed": "No se pudo actualizar el idioma.",
      "settings.privacy": "Privacidad",
      "settings.notifications": "Notificaciones",
      "settings.security": "Seguridad",
      "settings.app_permissions": "Permisos de la app",
      "settings.legal_safety": "Legal y seguridad",
      "settings.support": "Soporte",
      "settings.manage_account": "Administra tu cuenta",
      "settings.restart_to_apply": "Reinicia Captro para aplicar el idioma.",
      "legal.terms": "Términos de servicio",
      "legal.privacy": "Política de privacidad",
      "legal.community": "Normas de la comunidad",
      "legal.safety": "Seguridad y reportes",
      "ugc.see_translation": "Ver traducción",
      "ugc.view_original": "Ver original",
      "notification.like": "A %@ le gustó tu publicación.",
      "notification.comment": "%@ comentó tu publicación.",
      "notification.message": "Nuevo mensaje de %@",
      "error.username_taken": "Ese nombre de usuario ya está en uso.",
      "error.username_invalid": "Elige un nombre de usuario válido.",
      "error.post_not_found": "No se encontró la publicación.",
      "error.target_not_found": "No pudimos encontrar ese contenido.",
      "error.unauthorized": "Inicia sesión otra vez.",
      "error.upload_failed": "No se pudo subir. Inténtalo de nuevo.",
      "error.report_duplicate": "Ya reportaste esto.",
      "error.rate_limited": "Demasiados intentos. Inténtalo pronto.",
      "error.generic": "El servidor no pudo completar esta solicitud."
    ]
  ]

  static func value(for key: String, language: String) -> String {
    values[language]?[key] ?? values["en"]?[key] ?? key
  }
}
