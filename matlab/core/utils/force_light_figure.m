function force_light_figure(fig)
% FORCE_LIGHT_FIGURE  Render a figure on a light background before export.
%   Publication figures must not inherit a dark MATLAB desktop theme, which
%   otherwise exports black axes that are unusable in the manuscript.

    try
        theme(fig, 'light');                     % R2025a and newer
    catch
        set(fig, 'Color', 'w');
        for ax = findall(fig, 'Type', 'axes').'
            set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'ZColor', 'k', ...
                    'GridColor', [0.15 0.15 0.15]);
            set(get(ax, 'Title'), 'Color', 'k');
        end
    end
end
