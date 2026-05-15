use jni::objects::{JClass, JObject, JObjectArray, JString};
use jni::sys::{jobjectArray, jstring};
use jni::JNIEnv;

extern "C" {
    fn flames_cpp_engagement_score(
        likes: f64,
        comments: f64,
        shares: f64,
        saves: f64,
        impressions: f64,
    ) -> f64;
}

#[derive(Clone)]
struct FeedSignal {
    title: &'static str,
    category: &'static str,
    location: &'static str,
    likes: f64,
    comments: f64,
    shares: f64,
    saves: f64,
    impressions: f64,
    age_hours: f64,
    interest_match: f64,
    distance_km: f64,
}

#[no_mangle]
pub extern "system" fn Java_com_flamesup_nativeapp_NativeCore_initNativeCore(
    env: JNIEnv,
    _class: JClass,
) -> jstring {
    let score = unsafe { flames_cpp_engagement_score(420.0, 68.0, 31.0, 77.0, 9100.0) };
    let message = format!(
        "Native core ready. Kotlin -> JNI -> Rust -> C++ score {:.1}",
        score * 100.0
    );

    env.new_string(message)
        .expect("failed to allocate Java string")
        .into_raw()
}

#[no_mangle]
pub extern "system" fn Java_com_flamesup_nativeapp_NativeCore_rankPreview(
    mut env: JNIEnv,
    _class: JClass,
) -> jobjectArray {
    let ranked = rank_items(sample_feed());
    let string_class = env
        .find_class("java/lang/String")
        .expect("java/lang/String class missing");
    let output: JObjectArray = env
        .new_object_array(ranked.len() as i32, string_class, JObject::null())
        .expect("failed to allocate Java string array");

    for (index, value) in ranked.iter().enumerate() {
        let java_value: JString = env
            .new_string(value)
            .expect("failed to allocate Java string");
        env.set_object_array_element(&output, index as i32, java_value)
            .expect("failed to set Java array element");
    }

    output.into_raw()
}

fn sample_feed() -> Vec<FeedSignal> {
    vec![
        FeedSignal {
            title: "Streetwear drop in SoHo",
            category: "fashion",
            location: "SoHo",
            likes: 240.0,
            comments: 37.0,
            shares: 18.0,
            saves: 60.0,
            impressions: 4200.0,
            age_hours: 2.0,
            interest_match: 0.95,
            distance_km: 1.4,
        },
        FeedSignal {
            title: "Late night picnic loop",
            category: "social",
            location: "Bryant Park",
            likes: 178.0,
            comments: 22.0,
            shares: 11.0,
            saves: 45.0,
            impressions: 3300.0,
            age_hours: 0.5,
            interest_match: 0.74,
            distance_km: 2.8,
        },
        FeedSignal {
            title: "Gallery opening downtown",
            category: "art",
            location: "Lower East Side",
            likes: 198.0,
            comments: 31.0,
            shares: 14.0,
            saves: 58.0,
            impressions: 5100.0,
            age_hours: 5.5,
            interest_match: 0.9,
            distance_km: 1.7,
        },
        FeedSignal {
            title: "Club set after midnight",
            category: "nightlife",
            location: "Manhattan",
            likes: 321.0,
            comments: 48.0,
            shares: 26.0,
            saves: 52.0,
            impressions: 8700.0,
            age_hours: 1.2,
            interest_match: 0.88,
            distance_km: 4.2,
        },
    ]
}

fn rank_items(items: Vec<FeedSignal>) -> Vec<String> {
    let mut scored: Vec<(FeedSignal, f64)> = items
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
            let score = engagement * 0.44
                + recency * 0.24
                + item.interest_match * 0.22
                + proximity * 0.10;
            (item, score)
        })
        .collect();

    scored.sort_by(|a, b| b.1.total_cmp(&a.1));
    scored
        .into_iter()
        .map(|(item, score)| {
            format!(
                "{} • {} • {} • {:.0}",
                item.title,
                item.category,
                item.location,
                score * 100.0
            )
        })
        .collect()
}
