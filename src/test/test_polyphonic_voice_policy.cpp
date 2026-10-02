#include "../lib/catch2/single_include/catch2/catch.hpp"
#include "../resonance_polyphonic_voice_policy.h"

using namespace resonance;

TEST_CASE("two reflection apply readers on one source are rejected", "[polyphonic_voice]") {
    int32_t reader = -1;
    REQUIRE(claim_reflection_apply(&reader, kEmitterReflectionReader));
    REQUIRE_FALSE(claim_reflection_apply(&reader, 2));
    REQUIRE(reader == kEmitterReflectionReader);
    REQUIRE(claim_reflection_apply(&reader, kEmitterReflectionReader));
    reader = -1;
    REQUIRE(claim_reflection_apply(&reader, kEmitterReflectionReader));
}

TEST_CASE("a voice bound to the emitter may convolve that source", "[polyphonic_voice]") {
    REQUIRE(voice_may_convolve_source(4, 4));
    REQUIRE_FALSE(voice_may_convolve_source(-1, 4));
    REQUIRE_FALSE(voice_may_convolve_source(4, 8));
    REQUIRE(voice_tail_ir_matches_source(4, 4));
    REQUIRE_FALSE(voice_tail_ir_matches_source(4, 8));
    REQUIRE(voice_reflection_ir_generation_live(2u, 2u));
    REQUIRE_FALSE(voice_reflection_ir_generation_live(2u, 3u));
    REQUIRE_FALSE(voice_reflection_ir_generation_live(0u, 3u));
}
