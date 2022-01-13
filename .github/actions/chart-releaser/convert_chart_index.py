import yaml
import sys

if __name__ == '__main__':
    d = None
    if len(sys.argv) != 1:
        print("Usage: python convert_chart_index.py <path_to_yaml> ")
    yaml_file = sys.argv[1] #"test.yaml"
    with open(yaml_file, "r+") as f:
        d = yaml.safe_load(f)
        f.seek(0)
        for name, packages in d['entries'].items():
            for package in packages:
                package['urls'] = [('chart-packages/' + url.split('/')[-1]) if url.startswith('https://') else url for url in package['urls']] 
        f.truncate()
        yaml.dump(d, f)
