function tests = test_validation
% TEST_VALIDATION  Runs the verification suites of matlab/core/sim as unit tests.
%   Each suite raises an error when any of its checks fails.
%     validate_h1     tumbling target: quaternion norm, momentum and energy, capture-point kinematics (V1-V9)
%     validate_task1  LVLH frame, Clohessy-Wiltshire relative dynamics, keep-out safety function (T1-T10)
%     validate_task2  HOCBF-QP safety filter (V1-V19)
%     validate_task3  preview MPC with the HOCBF-QP filter in closed loop (W1-W15)
%   Run from the repository root:  results = runtests('tests/matlab');
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    set(groot, 'defaultFigureVisible', 'off');
end

function teardownOnce(~)
    close all force;
    set(groot, 'defaultFigureVisible', 'remove');
end

function test_h1_target_kinematics(~)
    run_suite('validate_h1');
end

function test_task1_cw_model(~)
    run_suite('validate_task1');
end

function test_task2_hocbf_filter(~)
    run_suite('validate_task2');
end

function test_task3_preview_mpc(~)
    run_suite('validate_task3');
end

function run_suite(name)
    root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    run(fullfile(root, 'matlab', 'core', 'sim', [name '.m']));
    close all force;
end
