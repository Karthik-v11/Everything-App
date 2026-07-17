import 'package:everything_app/data/services/dictation_normaliser.dart';
import 'package:flutter_test/flutter_test.dart';

/// The recogniser's inverse text normalisation, undone.
///
/// The reported bug: dictating "need to buy milk" arrived as "need 2 by milk".
/// The regressions worth guarding are in the other direction — this assistant
/// takes counts and amounts by voice, so a rule that rewrites the `2` in "buy 2
/// apples" would break more than it fixed.
void main() {
  group('digits the recogniser should not have formatted', () {
    test('rewrites the reported transcript', () {
      expect(normaliseDictation('need 2 by milk'), 'need to buy milk');
    });

    test('reads 2 as to in front of a verb', () {
      expect(normaliseDictation('2 call the dentist'), 'to call the dentist');
      expect(normaliseDictation('remind me 2 pay rent'), 'remind me to pay rent');
    });

    test('reads 2 as to behind a verb that takes one', () {
      expect(normaliseDictation('going 2 the gym'), 'going to the gym');
      expect(normaliseDictation('i forgot 2 water the plants'),
          'i forgot to water the plants');
    });

    test('reads 4 as for in front of a determiner', () {
      expect(normaliseDictation('coffee 4 the team'), 'coffee for the team');
      expect(normaliseDictation('book a table 4 me'), 'book a table for me');
    });

    test('expands & and @', () {
      expect(normaliseDictation('milk & eggs'), 'milk and eggs');
      expect(normaliseDictation('meet sam @ noon'), 'meet sam at noon');
    });
  });

  group('numbers that are really numbers', () {
    test('leaves a count in front of a noun alone', () {
      expect(normaliseDictation('buy 2 apples'), 'buy 2 apples');
      expect(normaliseDictation('4 bottles of water'), '4 bottles of water');
    });

    test('leaves an amount alone', () {
      expect(normaliseDictation('spent 2 on coffee'), 'spent 2 on coffee');
      expect(normaliseDictation('add 4 to the total'), 'add 4 to the total');
    });

    test('leaves a bare digit alone', () {
      expect(normaliseDictation('2'), '2');
      expect(normaliseDictation('4'), '4');
    });
  });

  group('by that is really by', () {
    test('keeps the preposition in an idiom', () {
      expect(normaliseDictation('finish it by tomorrow'), 'finish it by tomorrow');
      expect(normaliseDictation('send it by email'), 'send it by email');
    });

    test('keeps by the way', () {
      expect(normaliseDictation('to by the way'), 'to by the way');
    });

    test('rewrites by behind a modal', () {
      expect(normaliseDictation('should by eggs'), 'should buy eggs');
      expect(normaliseDictation('gonna by a charger'), 'gonna buy a charger');
    });
  });

  group('shape of the transcript', () {
    test('survives punctuation around the token', () {
      expect(normaliseDictation('need 2, buy milk'), 'need to, buy milk');
    });

    test('leaves an empty transcript alone', () {
      expect(normaliseDictation(''), '');
    });

    test('leaves a transcript with nothing to fix untouched', () {
      expect(normaliseDictation('call mum about the trip'),
          'call mum about the trip');
    });
  });
}
