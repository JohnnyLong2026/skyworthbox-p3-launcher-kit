package com.skyworthdigital.autostart;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.drawable.Drawable;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.ListView;
import android.widget.TextView;

import java.text.Collator;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/** Lists the installed apps the user may auto-start. Sideloaded apps only by default. */
public class AppPickerActivity extends Activity {

    static final String EXTRA_PKG = "pkg";
    static final String EXTRA_LABEL = "label";

    private final List<AppEntry> entries = new ArrayList<>();
    private final Map<String, Drawable> iconCache = new HashMap<>();
    private AppAdapter adapter;
    private ListView listView;
    private TextView emptyView;
    private Button toggleButton;
    private boolean includeSystemApps;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_picker);

        listView = findViewById(R.id.list_apps);
        emptyView = findViewById(R.id.tv_empty);
        toggleButton = findViewById(R.id.btn_toggle_system);

        adapter = new AppAdapter();
        listView.setAdapter(adapter);
        listView.setEmptyView(emptyView);

        toggleButton.setOnClickListener(v -> {
            includeSystemApps = !includeSystemApps;
            updateToggleLabel();
            reload();
        });

        listView.setOnItemClickListener((parent, view, position, id) -> {
            AppEntry entry = entries.get(position);
            Intent data = new Intent();
            data.putExtra(EXTRA_PKG, entry.pkg);
            data.putExtra(EXTRA_LABEL, entry.label);
            setResult(RESULT_OK, data);
            finish();
        });

        updateToggleLabel();
        reload();
    }

    private void updateToggleLabel() {
        toggleButton.setText(includeSystemApps ? R.string.all_apps : R.string.only_third_party);
        toggleButton.setSelected(includeSystemApps);
        toggleButton.setContentDescription(includeSystemApps ? "显示全部应用" : "仅显示第三方应用");
    }

    private void reload() {
        entries.clear();
        PackageManager pm = getPackageManager();
        String self = getPackageName();
        Set<String> homeApps = findHomeApps(pm);

        List<PackageInfo> installed = pm.getInstalledPackages(0);
        for (PackageInfo info : installed) {
            ApplicationInfo appInfo = info.applicationInfo;
            if (appInfo == null || self.equals(info.packageName)) {
                continue;
            }
            // A home screen cannot launch another home screen without bouncing straight back.
            if (homeApps.contains(info.packageName)) {
                continue;
            }
            boolean isSystem = (appInfo.flags
                    & (ApplicationInfo.FLAG_SYSTEM | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0;
            if (isSystem && !includeSystemApps) {
                continue;
            }
            // Only apps the launcher can actually open.
            Intent launch = pm.getLeanbackLaunchIntentForPackage(info.packageName);
            if (launch == null) {
                launch = pm.getLaunchIntentForPackage(info.packageName);
            }
            if (launch == null) {
                continue;
            }
            entries.add(new AppEntry(pm.getApplicationLabel(appInfo).toString(), info.packageName));
        }

        Collator collator = Collator.getInstance(Locale.CHINA);
        Collections.sort(entries, (a, b) -> collator.compare(a.label, b.label));

        adapter.notifyDataSetChanged();
        if (!entries.isEmpty()) {
            listView.requestFocus();
        }
    }

    private static Set<String> findHomeApps(PackageManager pm) {
        Set<String> result = new HashSet<>();
        Intent home = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME);
        for (ResolveInfo info : pm.queryIntentActivities(home, 0)) {
            if (info.activityInfo != null) {
                result.add(info.activityInfo.packageName);
            }
        }
        return result;
    }

    private static final class AppEntry {
        final String label;
        final String pkg;

        AppEntry(String label, String pkg) {
            this.label = label;
            this.pkg = pkg;
        }
    }

    private final class AppAdapter extends BaseAdapter {

        @Override
        public int getCount() {
            return entries.size();
        }

        @Override
        public Object getItem(int position) {
            return entries.get(position);
        }

        @Override
        public long getItemId(int position) {
            return position;
        }

        @Override
        public View getView(int position, View convertView, ViewGroup parent) {
            View view = convertView;
            if (view == null) {
                view = LayoutInflater.from(AppPickerActivity.this)
                        .inflate(R.layout.item_app, parent, false);
            }
            AppEntry entry = entries.get(position);
            ((TextView) view.findViewById(R.id.item_name)).setText(entry.label);
            ((TextView) view.findViewById(R.id.item_pkg)).setText(entry.pkg);

            ImageView icon = view.findViewById(R.id.item_icon);
            Drawable cached = iconCache.get(entry.pkg);
            if (cached == null) {
                try {
                    cached = getPackageManager().getApplicationIcon(entry.pkg);
                    iconCache.put(entry.pkg, cached);
                } catch (PackageManager.NameNotFoundException ignored) {
                    cached = null;
                }
            }
            icon.setImageDrawable(cached);
            return view;
        }
    }
}
