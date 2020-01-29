import { connect } from 'react-redux';
import RelativeLinks from '../components/relative_links';
import { toggleRelativeLinks } from '../../../actions/relative_links';

const mapStateToProps = (state) => ({
  visible: state.getIn(['relative_links', 'visible']),
});

const mapDispatchToProps = (dispatch) => ({
  onToggle () {
    dispatch(toggleRelativeLinks());
  },
});

export default connect(mapStateToProps, mapDispatchToProps)(RelativeLinks);
