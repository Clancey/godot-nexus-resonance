#ifndef RESONANCE_HRTF_RATE_POLICY_H
#define RESONANCE_HRTF_RATE_POLICY_H

namespace resonance {

/// Rates stored in the embedded default HRTF blob of Steam Audio 4.8.1.
/// Not a general Phonon limit: SOFA data is resampled to the pipeline rate.
/// Re-check the blob header when bumping the Steam Audio SDK.
inline bool default_hrtf_supports_sample_rate(int sample_rate) {
    return sample_rate == 24000 || sample_rate == 44100 || sample_rate == 48000;
}

} // namespace resonance

#endif // RESONANCE_HRTF_RATE_POLICY_H
