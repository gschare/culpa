import requests
from bs4 import BeautifulSoup
import re
import json
import sys
from os.path import exists

all_profs_url = "https://culpa.info/browse_by_prof"
prof_url = lambda prof_id: f"https://culpa.info/prof/{str(prof_id)}"
course_url = lambda course_id: f"https://culpa.info/course/{str(course_id)}"
review_url = lambda review_id: f"https://culpa.info/review/{str(review_id)}"

all_profs_file = "_pages/all_profs.html"
prof_file = lambda prof_id: f"_pages/prof/prof_{str(prof_id)}.html"
course_file = lambda course_id: f"_pages/course/course_{str(course_id)}.html"
review_file = lambda review_id: f"_pages/review/review_{str(review_id)}.html"

profs_json_file = "_data/professors.json"
courses_json_file = "_data/courses.json"
reviews_json_file = "_data/reviews.json"
depts_json_file = "_data/departments.json"

def regularize_dept(dept_id):
    dept_id = str(dept_id)
    return {
        "1": "AFAS",
        "60": "AMST",
        "2": "ANTH",
        "3": "APAM",
        "4": "ACLG",
        "5": "ARCH",
        "6": "AHIS",
        "7": "as-am studies",
        "8": "ASTR",
        "9": "BIOL", # bio and biomed eng
        "10": "BUSI",
        "11": "CSER",
        "12": "CHEM", # chem and chem eng
        "13": "CIEN",
        "14": "CLST",
        "15": "COMS",
        "62": "SUMA",
        "59": "COCI", # contains all core
        "16": "DNCE",
        "17": "EAEE",
        "18": "EESC",
        "19": "EAAS",
        "20": "EEEB",
        "21": "ECON",
        "22": "EDUC",
        "23": "ELEN",
        "24": "ENGL", # and comp lit
        "25": "FILM",
        "39": "FYSB",
        "26": "FREN",
        "27": "GERM",
        "28": "HIST",
        "29": "HRTS",
        "30": "IEOR",
        "31": "ITAL",
        "32": "LACV",
        "33": "LAW",
        "34": "MATH",
        "35": "MECE",
        "36": "MD",
        "37": "MDES",
        "38": "MUSI",
        "40": "PHIL",
        "41": "PHED",
        "64": "PHYT",
        "42": "PHYS",
        "43": "POLS",
        "44": "PSYC",
        "45": "RELI",
        "46": "SIPA",
        "61": "JOUR",
        "47": "SLLT", # all slavic
        "48": "SOCI",
        "49": "SPAN",
        "50": "ENGL", # speech
        "51": "STAT",
        "63": "SDEV",
        "52": "SWED",
        "53": "THTR",
        "54": "underwater bw",
        "55": "URBS",
        "56": "VIAR",
        "57": "WMST",
        "58": "WRIT"
        }[dept_id]


def download_all_profs_page():
    r = requests.get(all_profs_url)
    assert r.status_code == 200
    return r.text

def download_and_write_each_prof(profs):
    for prof_id, _ in profs.items():
        prof_html = download_prof_page(prof_id)
        with open(prof_file(prof_id), "w") as fp:
            print(prof_file(prof_id), profs[prof_id]['name'])
            fp.write(prof_html)

def read_all_profs_page():
    with open(all_profs_file, "r") as fp:
        html = fp.read()
    return html

def download_prof_page(prof_id):
    r = requests.get(prof_url(prof_id))
    assert r.status_code == 200
    return r.text

def read_prof_page(prof_id):
    with open(prof_file(prof_id), "r") as fp:
        html = fp.read()
    return html

def download_course_page(course_id):
    r = requests.get(course_url(course_id))
    assert r.status_code == 200
    return r.text

def download_and_write_course_page(course_id):
    text = download_course_page(course_id)
    with open(course_file(course_id), "w") as fp:
        fp.write(text)

def read_course_page(course_id):
    with open(course_file(course_id), "r") as fp:
        html = fp.read()
    return html

def download_review_page(review_id):
    r = requests.get(review_url(review_id))
    assert r.status_code == 200
    return r.text

def download_and_write_review_page(review_id):
    text = download_review_page(review_id)
    with open(review_file(review_id), "w") as fp:
        fp.write(text)

def read_review_page(review_id):
    with open(review_file(review_id), "r") as fp:
        html = fp.read()
    return html

def parse_all_profs(html):
    soup = BeautifulSoup(html, 'html.parser')

    # get profs
    prof_tags = soup.find_all(lambda tag:
        tag.name == 'a' and tag['href'].startswith("/prof/"))

    # sanity check
    accordion = soup.find('div', id='accordion')
    letters = accordion.find_all('button')

    n_profs = sum([
        int(re.search('\d+', letter.text).group(0))
        for letter in letters
        ])
    assert len(prof_tags) == n_profs

    profs = {}
    for tag in prof_tags:
        prof_id = int(re.search('\d+', tag['href']).group(0))
        assert prof_id not in profs, f'{prof_id} already exists'
        profs[prof_id] = {
            'prof_id':prof_id,
            'name':tag.text
            }
    return profs

# Professor JSON schema:
# { 1234: 
#       { "prof_id": 1234,
#         "name": "First Last",     # maybe change this for easier sorting
#         "depts": ["COMS", "MATH"],
#         "nugget": "none",         # or "gold" or "silver"
#         "courses": [5, 8, 27, 84],    # a list of course IDs
#         "reviews": [1850, 1385, 1345] # a list of review IDs
#       }
# }
def parse_prof(html):
    soup = BeautifulSoup(html, 'html.parser')
    prof = {}   # We will update the professor's JSON

    # professor data
    prof_data_table = soup.body.table

    # check for nugget
    nugget_line = prof_data_table.p.text.strip()

    if nugget_line == "":
        prof['nugget'] = 'none'
    elif 'gold' in nugget_line:
        prof['nugget'] = 'gold'
    elif 'silver' in nugget_line:
        prof['nugget'] = 'silver'
    else:
        assert False, "cannot parse nugget line: \"" + nugget_line + "\""

    # get departments
    prof_dept_tags = prof_data_table.find_all(
            lambda tag: tag.name == 'a' and tag['href'].startswith('/dept/'))
    prof['depts'] = []
    for tag in prof_dept_tags:
        prof['depts'].append(regularize_dept(tag['href'].split('/')[-1]))

    # get courses
    prof_course_tags = prof_data_table.find_all(
            lambda tag: tag.name == 'a' and tag['href'].startswith('/course/'))
    prof['courses'] = []
    for tag in prof_course_tags:
        prof['courses'].append(tag['href'].split('/')[-1])

    # get reviews
    prof['reviews'] = []
    review_tags = soup.find_all('div', class_='card')
    for tag in review_tags:
        if tag.get('data-reviewpk'):
            prof['reviews'].append(tag.get('data-reviewpk'))
        else:
            print("prof has no reviews")

    return prof

# Review JSON schema:
# { 1850:
#   { "review_id": 1850,
#     "date": "2022-08", # monthly only for anonymity
#     "course": 8,
#     "prof": 1234,
#     "content": "I hate this guy!"
#   }
# }
def parse_review(html):
    soup = BeautifulSoup(html, 'html.parser')
    review = {}
    if soup.find('div', class_='card') is not None:
        data_table = soup.find('div', class_='card').table
    else:
        return None

    # get course id
    course_tag = data_table.find(
            lambda t: t.name=='a' and
            t['href'].startswith('/course/'))
    if course_tag is not None:
        review['course_id'] = course_tag['href'].split('/')[-1]

    # get prof id
    review['prof_id'] = data_table.find(
            lambda t: t.name=='a' and
            t['href'].startswith('/prof/'))['href'].split('/')[-1]

    # get date
    review['date'] = data_table.find_all('td')[1].text.strip()

    # get content
    review['content'] = soup.find('p', class_='card-text').text

    return review

# Course JSON schema:
# { 8:
#       { "course_id": 8,
#         "depts": ["COMS"],
#         "name": "Advanced Programming",
#         "reviews": [...],
#         "profs": [...]
#       }
# }
def parse_course(html):
    soup = BeautifulSoup(html, 'html.parser')
    course = {}
    course_data_table = soup.table
    if course_data_table is None:
        return None

    # get course name
    course['name'] = course_data_table.find('h1').br.next.strip()

    # decide department
    course['depts'] = [
            regularize_dept(t['href'].split('/')[-1]) for t in
            course_data_table.find_all(
            lambda t: t.name=='a' and t['href'].startswith('/dept/'))
            ]

    # get profs
    course['profs'] = [
            t['href'].split('/')[-1] for t in
            course_data_table.find_all(
            lambda t: t.name=='a' and t['href'].startswith('/prof/'))
            ]

    # get reviews
    course['reviews'] = []
    review_tags = soup.find_all('div', class_='card')
    for tag in review_tags:
        if tag.get('data-reviewpk'):
            course['reviews'].append(tag.get('data-reviewpk'))
        else:
            print(f"course {course['name']} has no reviews")
    return course

def write_profs_json(profs):
    with open(profs_json_file, "w") as fp:
        fp.write(json.dumps(profs, sort_keys=True, indent=4))

def write_courses_json(courses):
    with open(courses_json_file, "w") as fp:
        fp.write(json.dumps(courses, sort_keys=True, indent=4))

def write_reviews_json(reviews):
    with open(reviews_json_file, "w") as fp:
        fp.write(json.dumps(reviews, sort_keys=True, indent=4))

def verify_courses(profs):
    for prof_id, prof in profs.items():
        for course in prof['courses']:
            assert exists(course_file(course)), f"course {str(course)} not found for prof {str(prof_id)}"

def verify_reviews(profs):
    for prof_id, prof in profs.items():
        for review in prof['reviews']:
            assert exists(review_file(review)), f"review {str(review)} not found for prof {str(prof_id)}"

def load_profs_json():
    with open(profs_json_file, "r") as fp:
        profs = json.loads(fp.read())
    return profs

def load_reviews_json():
    with open(reviews_json_file, "r") as fp:
        reviews = json.loads(fp.read())
    return reviews

def load_courses_json():
    with open(courses_json_file, "r") as fp:
        courses = json.loads(fp.read())
    return courses

def parse_courses_and_reviews(profs):
    for prof_id, prof in profs.items():
        print('prof', prof_id)
        for course_id in prof['courses']:
            print('course', course_id)
            if course_id not in courses:
                courses[course_id] = parse_course(read_course_page(course_id))
                if courses[course_id] is not None:
                    courses[course_id]['course_id'] = course_id
            else:
                print('course', course_id, "already seen", file=sys.stderr)
        for review_id in prof['reviews']:
            print('review', review_id)
            if review_id not in reviews:
                reviews[review_id] = parse_review(read_review_page(review_id))
                if reviews[review_id] is not None:
                    reviews[review_id]['review_id'] = review_id
            else:
                print('review', review_id, "already seen", file=sys.stderr)

def main():
    profs = load_profs_json()
    courses = load_courses_json()
    reviews = load_reviews_json()

    # TODO:
    #   * fix the bad department codes

if __name__ == "__main__":
    main()
