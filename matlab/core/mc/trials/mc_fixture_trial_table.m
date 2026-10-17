function T = mc_fixture_trial_table(seed, n)
% MC_FIXTURE_TRIAL_TABLE  A NON-SCIENTIFIC trial table from a FIXTURE seed.
%   T = mc_fixture_trial_table(seed, n) builds n trial rows with exactly the
%   scientific draw pattern (Sec. 3.3: a DEDICATED mt19937ar RandStream,
%   rand(stream, 15, n), column-major) and the frozen mapping, but from a
%   FIXTURE seed. It exists only for the verification suite (Sec. 10.2).
%
%   RNG FIREWALL. The scientific seed is REFUSED here with
%   'mc:rng:scientific_seed_forbidden' BEFORE any stream is constructed. The
%   global stream is never touched. The result is labelled kind = 'FIXTURE';
%   no writer in src/mc will place any caller-held table under results/task4/mc.

    c = mc_constants();
    assert(isnumeric(seed) && isscalar(seed) && isreal(seed) && seed == round(seed) ...
        && seed >= 0 && seed < 2^32, 'mc:rng:seed', ...
        'A fixture seed must be an integer in [0, 2^32).');
    if seed == c.rng.seed
        error('mc:rng:scientific_seed_forbidden', ...
            ['REFUSED: %d is the SCIENTIFIC seed. Fixture tables may never use it; ' ...
             'only MC_SCIENTIFIC_TRIAL_TABLE may, after the generation preflight.'], seed);
    end
    assert(isnumeric(n) && isscalar(n) && n == round(n) && n >= 1 && n <= 1000, ...
        'mc:rng:n', 'n must be an integer in [1, 1000].');

    stream = RandStream(c.rng.generator, 'Seed', seed);
    U = rand(stream, c.design.n_draws, n);
    T = mc_trial_table_from_U(U, 'FIXTURE');
    T.seed      = seed;
    T.generator = c.rng.generator;
end
