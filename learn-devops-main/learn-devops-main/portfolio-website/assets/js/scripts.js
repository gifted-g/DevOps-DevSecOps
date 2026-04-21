document.addEventListener('DOMContentLoaded', function() {
    var seeMoreButton = document.getElementById('see-more');
    var moreCourses = document.getElementById('more-courses');

    seeMoreButton.addEventListener('click', function() {
        if (moreCourses.style.display === 'none') {
            moreCourses.style.display = 'block';
            seeMoreButton.textContent = 'See Less';
        } else {
            moreCourses.style.display = 'none';
            seeMoreButton.textContent = 'See More';
        }
    });
});
