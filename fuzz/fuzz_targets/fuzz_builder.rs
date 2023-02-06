#![no_main]

use libfuzzer_sys::{arbitrary::Arbitrary, arbitrary::Unstructured, arbitrary::Result, fuzz_target};

extern crate grex;

use grex::{RegExpBuilder, RegExpConfig};

#[derive(Debug, Clone)]
struct ByteString<'a> {
    bytes: &'a [u8],
}

impl<'a> Into<String> for ByteString<'a> {
    fn into(self) -> String {
        String::from_utf8_lossy(self.bytes).to_string()
    }
}

const STRING_COUNT: usize = 4;
const STRING_LENGTH: usize = 15;

#[derive(Debug)]
struct InputData<'a> {
    // limits the number of strings used
    num_strings: u8,
    bytes: [&'a [u8]; STRING_COUNT]
}

#[derive(Arbitrary, Debug)]
struct TestInput<'a> {
    is_digit_converted: bool,
    is_non_digit_converted: bool,
    is_space_converted: bool,
    is_non_space_converted: bool,
    is_word_converted: bool,
    is_non_word_converted: bool,
    is_capturing_group_enabled: bool,
    is_non_ascii_char_escaped: bool,
    is_astral_code_point_converted_to_surrogate: bool,
    is_start_anchor_disabled: bool,
    is_end_anchor_disabled: bool,
    is_output_colorized: bool,

    data: InputData<'a>
}

impl<'a> Arbitrary<'a> for InputData<'a> {
    fn arbitrary(u: &mut Unstructured<'a>) -> Result<Self> {
        let mut input_bytes = [[].as_slice(); STRING_COUNT];
        let num_strings = u.int_in_range(1..=(STRING_COUNT as u8))?;

        let mut current_string = 0 as usize;
        while current_string < num_strings as usize && !u.is_empty() {
            let bytes_remaining = u.len();
            let max_length = STRING_LENGTH.min(bytes_remaining) as u8;

            let string_size = u.int_in_range(0..=max_length)?;
            // now, let's get that many
            input_bytes[current_string] = u.bytes(string_size as usize)?;

            current_string += 1;
        }

        Ok(InputData { num_strings, bytes: input_bytes })
    }

    fn size_hint(_depth: usize) -> (usize, Option<usize>) {
        let min = 0;
        // 1: number of strings
        // 1: size of each string
        let max = 1 + (1 + STRING_LENGTH) * STRING_COUNT;

        (min, Some(max))
    }
}

fuzz_target!(|input: TestInput| {
    let mut input = input;

    let config = RegExpConfig {
        // these parameters are not used unless is_repetition_converted is true
        minimum_repetitions: 0,
        minimum_substring_length: 0,

        is_digit_converted: input.is_digit_converted,
        is_non_digit_converted: input.is_non_digit_converted,
        is_space_converted: input.is_space_converted,
        is_non_space_converted: input.is_non_space_converted,
        is_word_converted: input.is_word_converted,
        is_non_word_converted: input.is_non_word_converted,

        // disable for efficiency
        is_repetition_converted: false,

        // disable for efficiency
        is_case_insensitive_matching: false,

        is_capturing_group_enabled: input.is_capturing_group_enabled,
        is_non_ascii_char_escaped: input.is_non_ascii_char_escaped,
        is_astral_code_point_converted_to_surrogate: input.is_astral_code_point_converted_to_surrogate,

        // disable verbose mode since it's slow
        is_verbose_mode_enabled: false,

        is_start_anchor_disabled: input.is_start_anchor_disabled,
        is_end_anchor_disabled: input.is_end_anchor_disabled,
        is_output_colorized: input.is_output_colorized,
    };

    let input_data = input.data.bytes.iter().take(input.data.num_strings as usize).map(|s| String::from_utf8_lossy(&s[..])).collect::<Vec<_>>();

    let mut builder = RegExpBuilder::from(&input_data);
    builder.config = config;

    let _ = builder.build();
});
