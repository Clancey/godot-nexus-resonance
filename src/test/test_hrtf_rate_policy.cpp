#include "../lib/catch2/single_include/catch2/catch.hpp"
#include "../resonance_hrtf_rate_policy.h"

using namespace resonance;

TEST_CASE("Steam Audio 4.8.1 default HRTF supports 24000, 44100, and 48000", "[hrtf][rate]") {
    REQUIRE(default_hrtf_supports_sample_rate(24000));
    REQUIRE(default_hrtf_supports_sample_rate(44100));
    REQUIRE(default_hrtf_supports_sample_rate(48000));
}

TEST_CASE("Steam Audio 4.8.1 default HRTF rejects rates absent from the embedded blob", "[hrtf][rate]") {
    REQUIRE_FALSE(default_hrtf_supports_sample_rate(96000));
    REQUIRE_FALSE(default_hrtf_supports_sample_rate(22050));
    REQUIRE_FALSE(default_hrtf_supports_sample_rate(192000));
    REQUIRE_FALSE(default_hrtf_supports_sample_rate(8000));
    REQUIRE_FALSE(default_hrtf_supports_sample_rate(0));
}
