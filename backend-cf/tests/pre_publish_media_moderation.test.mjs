import assert from 'node:assert/strict';
import test from 'node:test';

function decide(scores, mediaType = 'image', aiPolicy = '') {
  const reasons = [];
  if (scores.malware_status === 'malicious') reasons.push('malware_detected');
  if (scores.adult_explicit_score >= 0.85) reasons.push('explicit_sexual_content');
  if (scores.minor_safety_risk_score >= 0.20) reasons.push('minor_safety_risk');
  if (scores.gore_score >= 0.90) reasons.push('graphic_gore');
  if (scores.hate_symbol_score >= 0.85) reasons.push('hate_symbol');
  if (scores.spam_scam_score >= 0.90 || scores.link_risk_score >= 0.90) reasons.push('spam_or_scam');
  if (aiPolicy === 'disallow' && scores.ai_generated_likelihood >= 0.92) reasons.push('ai_generated_media');
  if (reasons.length) return { decision: 'rejected', reasons };
  const reviewReasons = [];
  if (scores.nudity_score >= 0.45) reviewReasons.push('nudity_review');
  if (scores.sexual_context_score >= 0.40) reviewReasons.push('sexual_context_review');
  if (scores.violence_score >= 0.55) reviewReasons.push('violence_review');
  if (scores.ai_generated_likelihood >= 0.65) reviewReasons.push('ai_generated_review');
  if (scores.confidence < 0.65) reviewReasons.push('low_model_confidence');
  if (scores.malware_status === 'unknown' && mediaType === 'video') reviewReasons.push('malware_scan_unknown_video');
  if (reviewReasons.length) return { decision: 'review_required', reasons: reviewReasons };
  return { decision: 'approved', reasons: [] };
}

const safe = {
  adult_explicit_score: 0.01,
  nudity_score: 0.02,
  sexual_context_score: 0.03,
  sexual_solicitation_score: 0,
  minor_safety_risk_score: 0,
  violence_score: 0.04,
  gore_score: 0,
  weapon_score: 0,
  hate_symbol_score: 0,
  ai_generated_likelihood: 0.05,
  spam_scam_score: 0,
  malware_status: 'clean',
  link_risk_score: 0,
  confidence: 0.91,
};

test('approves low-risk image uploads', () => {
  assert.equal(decide(safe, 'image').decision, 'approved');
});

test('rejects high-risk media before publish', () => {
  assert.equal(decide({ ...safe, adult_explicit_score: 0.91 }, 'image').decision, 'rejected');
  assert.equal(decide({ ...safe, malware_status: 'malicious' }, 'image').decision, 'rejected');
  assert.equal(decide({ ...safe, hate_symbol_score: 0.9 }, 'image').decision, 'rejected');
});

test('sends ambiguous media to admin review', () => {
  assert.equal(decide({ ...safe, nudity_score: 0.5 }, 'image').decision, 'review_required');
  assert.equal(decide({ ...safe, confidence: 0.5 }, 'image').decision, 'review_required');
  assert.equal(decide({ ...safe, malware_status: 'unknown' }, 'video').decision, 'review_required');
});

test('does not reject AI-generated likelihood unless policy disallows at high confidence', () => {
  assert.equal(decide({ ...safe, ai_generated_likelihood: 0.7 }, 'image').decision, 'review_required');
  assert.equal(decide({ ...safe, ai_generated_likelihood: 0.93 }, 'image', 'disallow').decision, 'rejected');
});
