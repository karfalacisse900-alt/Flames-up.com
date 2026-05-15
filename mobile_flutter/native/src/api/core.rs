#[derive(Debug, Clone)]
pub struct NativeCoreStatus {
    pub engine_name: String,
    pub rust_ready: bool,
    pub cpp_ready: bool,
    pub sample_score: f64,
    pub message: String,
}

#[derive(Debug, Clone)]
pub struct FeedSignal {
    pub id: String,
    pub title: String,
    pub category: String,
    pub location: String,
    pub likes: f64,
    pub comments: f64,
    pub shares: f64,
    pub saves: f64,
    pub impressions: f64,
    pub age_hours: f64,
    pub interest_match: f64,
    pub distance_km: f64,
}

#[derive(Debug, Clone)]
pub struct RankedFeedItem {
    pub id: String,
    pub title: String,
    pub score: f64,
    pub reason: String,
}

extern "C" {
    fn flames_cpp_engagement_score(
        likes: f64,
        comments: f64,
        shares: f64,
        saves: f64,
        impressions: f64,
    ) -> f64;
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

#[flutter_rust_bridge::frb(sync)]
pub fn init_native_core() -> NativeCoreStatus {
    let sample_score = unsafe { flames_cpp_engagement_score(420.0, 68.0, 31.0, 77.0, 9100.0) };

    NativeCoreStatus {
        engine_name: "Flames Native Core".to_string(),
        rust_ready: true,
        cpp_ready: sample_score > 0.0,
        sample_score,
        message: "Flutter UI connected to Rust, with C++ compiled into the native crate.".to_string(),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn rank_for_you_items(items: Vec<FeedSignal>) -> Vec<RankedFeedItem> {
    let mut scored: Vec<RankedFeedItem> = items
        .into_iter()
        .map(|item| {
            let engagement = unsafe {
                flames_cpp_engagement_score(
                    item.likes,
                    item.comments,
                    item.shares,
                    item.saves,
                    item.impressions,
                )
            };
            let recency = (-item.age_hours / 36.0).exp();
            let proximity = (-item.distance_km / 20.0).exp();
            let affinity = item.interest_match.clamp(0.0, 1.0);
            let score = engagement * 0.44 + recency * 0.24 + affinity * 0.22 + proximity * 0.10;
            let reason = build_reason(engagement, recency, affinity, proximity, &item);

            RankedFeedItem {
                id: item.id,
                title: item.title,
                score,
                reason,
            }
        })
        .collect();

    scored.sort_by(|a, b| b.score.total_cmp(&a.score));
    scored
}

fn build_reason(
    engagement: f64,
    recency: f64,
    affinity: f64,
    proximity: f64,
    item: &FeedSignal,
) -> String {
    let mut reasons = Vec::new();

    if affinity >= 0.72 {
        reasons.push(format!("matches {}", item.category));
    }
    if recency >= 0.72 {
        reasons.push("fresh".to_string());
    }
    if engagement >= 0.35 {
        reasons.push("trending".to_string());
    }
    if proximity >= 0.55 {
        reasons.push(format!("near {}", item.location));
    }

    if reasons.is_empty() {
        "balanced recommendation".to_string()
    } else {
        reasons.join(" + ")
    }
}
